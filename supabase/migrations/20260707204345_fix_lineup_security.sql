-- =====================================================================
-- BAGREFUT - Fix lineup security and integrity
-- =====================================================================

-- Authenticated users must mutate lineups only through public.save_lineup(...).
REVOKE INSERT, UPDATE, DELETE ON public.lineups FROM authenticated;
REVOKE INSERT, UPDATE, DELETE ON public.lineup_players FROM authenticated;
GRANT SELECT ON public.lineups TO authenticated;
GRANT SELECT ON public.lineup_players TO authenticated;

-- Slot identity is position + index. The original unique slot_index constraint
-- was too broad for position-scoped slots such as DEF 1 and MID 1.
ALTER TABLE public.lineup_players
  DROP CONSTRAINT IF EXISTS lineup_players_lineup_id_slot_index_key;

DO $$
BEGIN
  IF EXISTS (
    SELECT 1
    FROM public.lineup_players lp
    GROUP BY lp.lineup_id, lp.slot_position, lp.slot_index
    HAVING pg_catalog.count(*) > 1
  ) THEN
    RAISE EXCEPTION 'lineup_players_duplicate_slot_position_index';
  END IF;

  IF NOT EXISTS (
    SELECT 1
    FROM pg_catalog.pg_constraint c
    JOIN pg_catalog.pg_class t ON t.oid = c.conrelid
    JOIN pg_catalog.pg_namespace n ON n.oid = t.relnamespace
    WHERE n.nspname = 'public'
      AND t.relname = 'lineup_players'
      AND c.conname = 'lineup_players_lineup_slot_position_index_unique'
  ) THEN
    ALTER TABLE public.lineup_players
      ADD CONSTRAINT lineup_players_lineup_slot_position_index_unique
      UNIQUE (lineup_id, slot_position, slot_index);
  END IF;

  IF NOT EXISTS (
    SELECT 1
    FROM pg_catalog.pg_constraint c
    JOIN pg_catalog.pg_class t ON t.oid = c.conrelid
    JOIN pg_catalog.pg_namespace n ON n.oid = t.relnamespace
    WHERE n.nspname = 'public'
      AND t.relname = 'lineup_players'
      AND c.conname = 'lineup_players_slot_index_positive'
  ) THEN
    ALTER TABLE public.lineup_players
      ADD CONSTRAINT lineup_players_slot_index_positive
      CHECK (slot_index > 0);
  END IF;
END;
$$;

DROP POLICY IF EXISTS "lineups_owner_read" ON public.lineups;
DROP POLICY IF EXISTS "lineups_owner_insert" ON public.lineups;
DROP POLICY IF EXISTS "lineups_owner_update" ON public.lineups;

CREATE POLICY "lineups_owner_admin_or_released_read"
ON public.lineups
FOR SELECT
TO authenticated
USING (
  public.has_role(auth.uid(), 'admin')
  OR EXISTS (
    SELECT 1
    FROM public.clubs c
    WHERE c.id = lineups.club_id
      AND c.owner_id = auth.uid()
  )
  OR (
    EXISTS (
      SELECT 1
      FROM public.profiles p
      WHERE p.id = auth.uid()
        AND p.status = 'approved'
    )
    AND EXISTS (
      SELECT 1
      FROM public.rounds r
      WHERE r.id = lineups.round_id
        AND r.lineup_lock_at <= pg_catalog.now()
    )
  )
);

DROP POLICY IF EXISTS "lineup_players_owner_all" ON public.lineup_players;

CREATE POLICY "lineup_players_owner_admin_or_released_read"
ON public.lineup_players
FOR SELECT
TO authenticated
USING (
  EXISTS (
    SELECT 1
    FROM public.lineups l
    JOIN public.clubs c ON c.id = l.club_id
    WHERE l.id = lineup_players.lineup_id
      AND (
        c.owner_id = auth.uid()
        OR public.has_role(auth.uid(), 'admin')
        OR (
          EXISTS (
            SELECT 1
            FROM public.profiles p
            WHERE p.id = auth.uid()
              AND p.status = 'approved'
          )
          AND EXISTS (
            SELECT 1
            FROM public.rounds r
            WHERE r.id = l.round_id
              AND r.lineup_lock_at <= pg_catalog.now()
          )
        )
      )
  )
);

DROP FUNCTION IF EXISTS public.save_lineup(uuid, public.formation, public.play_style, jsonb);

CREATE OR REPLACE FUNCTION public.save_lineup(
  _round_id uuid,
  _formation public.formation,
  _play_style public.play_style,
  _players jsonb
)
RETURNS TABLE(
  lineup_id uuid,
  club_id uuid,
  round_id uuid,
  formation public.formation,
  play_style public.play_style,
  player_count integer,
  starter_count integer,
  saved_at timestamptz
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  _uid uuid := auth.uid();
  _profile public.profiles%ROWTYPE;
  _club public.clubs%ROWTYPE;
  _round public.rounds%ROWTYPE;
  _season public.seasons%ROWTYPE;
  _lineup public.lineups%ROWTYPE;
  _player_count integer;
  _starter_count integer;
  _expected_gk integer;
  _expected_def integer;
  _expected_mid integer;
  _expected_ata integer;
  _actual_gk integer;
  _actual_def integer;
  _actual_mid integer;
  _actual_ata integer;
  _owned_count integer;
  _saved_at timestamptz := pg_catalog.now();
BEGIN
  IF _uid IS NULL THEN
    RAISE EXCEPTION 'unauthenticated';
  END IF;

  SELECT *
  INTO _profile
  FROM public.profiles
  WHERE id = _uid;

  IF _profile.id IS NULL THEN
    RAISE EXCEPTION 'profile_not_found';
  END IF;

  IF _profile.status <> 'approved' THEN
    RAISE EXCEPTION 'profile_not_approved';
  END IF;

  SELECT *
  INTO _club
  FROM public.clubs
  WHERE owner_id = _uid
  FOR UPDATE;

  IF _club.id IS NULL THEN
    RAISE EXCEPTION 'club_not_found';
  END IF;

  SELECT *
  INTO _round
  FROM public.rounds
  WHERE id = _round_id
  FOR UPDATE;

  IF _round.id IS NULL THEN
    RAISE EXCEPTION 'round_not_found';
  END IF;

  SELECT *
  INTO _season
  FROM public.seasons
  WHERE id = _round.season_id;

  IF _season.id IS NULL THEN
    RAISE EXCEPTION 'season_not_found';
  END IF;

  IF _season.status <> 'active' THEN
    RAISE EXCEPTION 'season_not_active';
  END IF;

  IF _season.league_id <> _club.league_id THEN
    RAISE EXCEPTION 'league_mismatch';
  END IF;

  IF pg_catalog.now() >= _round.lineup_lock_at THEN
    RAISE EXCEPTION 'lineup_locked';
  END IF;

  IF _formation IS NULL THEN
    RAISE EXCEPTION 'invalid_formation';
  END IF;

  IF _play_style IS NULL THEN
    RAISE EXCEPTION 'invalid_play_style';
  END IF;

  IF _players IS NULL OR pg_catalog.jsonb_typeof(_players) <> 'array' THEN
    RAISE EXCEPTION 'invalid_players_payload';
  END IF;

  DROP TABLE IF EXISTS pg_temp.save_lineup_players_input;

  CREATE TEMP TABLE pg_temp.save_lineup_players_input (
    club_player_id uuid,
    slot_position public.player_position,
    is_starter boolean,
    slot_index integer
  ) ON COMMIT DROP;

  INSERT INTO pg_temp.save_lineup_players_input (
    club_player_id,
    slot_position,
    is_starter,
    slot_index
  )
  SELECT
    parsed.club_player_id,
    parsed.slot_position,
    parsed.is_starter,
    parsed.slot_index
  FROM pg_catalog.jsonb_to_recordset(_players) AS parsed(
    club_player_id uuid,
    slot_position public.player_position,
    is_starter boolean,
    slot_index integer
  );

  IF EXISTS (
    SELECT 1
    FROM pg_temp.save_lineup_players_input input
    WHERE input.club_player_id IS NULL
       OR input.slot_position IS NULL
       OR input.is_starter IS NULL
       OR input.slot_index IS NULL
  ) THEN
    RAISE EXCEPTION 'invalid_players_payload';
  END IF;

  IF EXISTS (
    SELECT 1
    FROM pg_temp.save_lineup_players_input input
    WHERE input.slot_index <= 0
       OR input.slot_index > 10
  ) THEN
    RAISE EXCEPTION 'invalid_slot_index';
  END IF;

  SELECT
    pg_catalog.count(*)::integer,
    pg_catalog.count(*) FILTER (WHERE input.is_starter)::integer
  INTO _player_count, _starter_count
  FROM pg_temp.save_lineup_players_input input;

  IF _player_count < 5 OR _player_count > 10 THEN
    RAISE EXCEPTION 'invalid_player_count';
  END IF;

  IF _starter_count <> 5 THEN
    RAISE EXCEPTION 'invalid_starter_count';
  END IF;

  IF (_player_count - _starter_count) > 5 THEN
    RAISE EXCEPTION 'too_many_reserves';
  END IF;

  IF EXISTS (
    SELECT 1
    FROM pg_temp.save_lineup_players_input input
    GROUP BY input.club_player_id
    HAVING pg_catalog.count(*) > 1
  ) THEN
    RAISE EXCEPTION 'duplicate_club_player';
  END IF;

  IF EXISTS (
    SELECT 1
    FROM pg_temp.save_lineup_players_input input
    GROUP BY input.slot_position, input.slot_index
    HAVING pg_catalog.count(*) > 1
  ) THEN
    RAISE EXCEPTION 'duplicate_slot';
  END IF;

  PERFORM 1
  FROM public.club_players cp
  JOIN pg_temp.save_lineup_players_input input ON input.club_player_id = cp.id
  WHERE cp.club_id = _club.id
  FOR UPDATE OF cp;

  SELECT pg_catalog.count(*)::integer
  INTO _owned_count
  FROM pg_temp.save_lineup_players_input input
  JOIN public.club_players cp ON cp.id = input.club_player_id
  WHERE cp.club_id = _club.id;

  IF _owned_count <> _player_count THEN
    RAISE EXCEPTION 'club_player_not_owned';
  END IF;

  IF EXISTS (
    SELECT 1
    FROM pg_temp.save_lineup_players_input input
    JOIN public.club_players cp ON cp.id = input.club_player_id
    WHERE cp.is_reserved
  ) THEN
    RAISE EXCEPTION 'club_player_reserved';
  END IF;

  IF EXISTS (
    SELECT 1
    FROM pg_temp.save_lineup_players_input input
    JOIN public.market_listings ml ON ml.club_player_id = input.club_player_id
    WHERE ml.status = 'open'
  ) THEN
    RAISE EXCEPTION 'club_player_reserved';
  END IF;

  IF EXISTS (
    SELECT 1
    FROM pg_temp.save_lineup_players_input input
    JOIN public.transfer_offer_items toi ON toi.club_player_id = input.club_player_id
    JOIN public.transfer_offers offer ON offer.id = toi.offer_id
    WHERE offer.status = 'pending'
      AND offer.expires_at > pg_catalog.now()
  ) THEN
    RAISE EXCEPTION 'club_player_reserved';
  END IF;

  _expected_gk := CASE _formation
    WHEN '1-2-1-1'::public.formation THEN 1
    WHEN '1-1-2-1'::public.formation THEN 1
    WHEN '1-1-1-2'::public.formation THEN 1
    WHEN '0-2-2-1'::public.formation THEN 0
  END;
  _expected_def := CASE _formation
    WHEN '1-2-1-1'::public.formation THEN 2
    WHEN '1-1-2-1'::public.formation THEN 1
    WHEN '1-1-1-2'::public.formation THEN 1
    WHEN '0-2-2-1'::public.formation THEN 2
  END;
  _expected_mid := CASE _formation
    WHEN '1-2-1-1'::public.formation THEN 1
    WHEN '1-1-2-1'::public.formation THEN 2
    WHEN '1-1-1-2'::public.formation THEN 1
    WHEN '0-2-2-1'::public.formation THEN 2
  END;
  _expected_ata := CASE _formation
    WHEN '1-2-1-1'::public.formation THEN 1
    WHEN '1-1-2-1'::public.formation THEN 1
    WHEN '1-1-1-2'::public.formation THEN 2
    WHEN '0-2-2-1'::public.formation THEN 1
  END;

  SELECT
    pg_catalog.count(*) FILTER (WHERE input.is_starter AND input.slot_position = 'GK')::integer,
    pg_catalog.count(*) FILTER (WHERE input.is_starter AND input.slot_position = 'DEF')::integer,
    pg_catalog.count(*) FILTER (WHERE input.is_starter AND input.slot_position = 'MID')::integer,
    pg_catalog.count(*) FILTER (WHERE input.is_starter AND input.slot_position = 'ATA')::integer
  INTO _actual_gk, _actual_def, _actual_mid, _actual_ata
  FROM pg_temp.save_lineup_players_input input;

  IF _actual_gk <> _expected_gk
     OR _actual_def <> _expected_def
     OR _actual_mid <> _expected_mid
     OR _actual_ata <> _expected_ata THEN
    RAISE EXCEPTION 'formation_slot_mismatch';
  END IF;

  IF EXISTS (
    SELECT 1
    FROM pg_temp.save_lineup_players_input input
    WHERE input.is_starter
      AND (
        (input.slot_position = 'GK' AND (input.slot_index < 1 OR input.slot_index > _expected_gk))
        OR (input.slot_position = 'DEF' AND (input.slot_index < 1 OR input.slot_index > _expected_def))
        OR (input.slot_position = 'MID' AND (input.slot_index < 1 OR input.slot_index > _expected_mid))
        OR (input.slot_position = 'ATA' AND (input.slot_index < 1 OR input.slot_index > _expected_ata))
      )
  ) THEN
    RAISE EXCEPTION 'formation_slot_mismatch';
  END IF;

  SELECT *
  INTO _lineup
  FROM public.lineups l
  WHERE l.club_id = _club.id
    AND l.round_id = _round.id
  FOR UPDATE;

  IF _lineup.id IS NULL THEN
    INSERT INTO public.lineups (
      club_id,
      round_id,
      formation,
      play_style,
      is_auto_generated,
      updated_at
    )
    VALUES (
      _club.id,
      _round.id,
      _formation,
      _play_style,
      false,
      _saved_at
    )
    RETURNING * INTO _lineup;
  ELSE
    UPDATE public.lineups
    SET formation = _formation,
        play_style = _play_style,
        is_auto_generated = false,
        updated_at = _saved_at
    WHERE id = _lineup.id
    RETURNING * INTO _lineup;
  END IF;

  DELETE FROM public.lineup_players lp
  WHERE lp.lineup_id = _lineup.id;

  INSERT INTO public.lineup_players (
    lineup_id,
    club_player_id,
    slot_position,
    is_starter,
    slot_index
  )
  SELECT
    _lineup.id,
    input.club_player_id,
    input.slot_position,
    input.is_starter,
    input.slot_index::smallint
  FROM pg_temp.save_lineup_players_input input
  ORDER BY input.is_starter DESC, input.slot_position, input.slot_index;

  RETURN QUERY
  SELECT
    _lineup.id AS lineup_id,
    _club.id AS club_id,
    _round.id AS round_id,
    _lineup.formation,
    _lineup.play_style,
    _player_count,
    _starter_count,
    _lineup.updated_at AS saved_at;
END;
$$;

REVOKE ALL ON FUNCTION public.save_lineup(uuid, public.formation, public.play_style, jsonb) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.save_lineup(uuid, public.formation, public.play_style, jsonb) TO authenticated;
