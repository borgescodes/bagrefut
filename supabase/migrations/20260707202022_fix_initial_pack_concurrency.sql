-- =====================================================================
-- BAGREFUT - Fix initial pack global distribution concurrency
-- =====================================================================

DROP FUNCTION IF EXISTS public.open_initial_pack(uuid);

CREATE OR REPLACE FUNCTION public.open_initial_pack(_club_id uuid)
RETURNS TABLE(
  pack_id uuid,
  club_id uuid,
  opened_at timestamptz,
  player_id uuid,
  slot smallint
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  _uid uuid := auth.uid();
  _profile public.profiles%ROWTYPE;
  _club public.clubs%ROWTYPE;
  _league public.leagues%ROWTYPE;
  _pack public.initial_packs%ROWTYPE;
  _picked_ids uuid[];
  _available_count integer;
  _inserted_count integer;
  _opened_at timestamptz;
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
  WHERE id = _club_id
  FOR UPDATE;

  IF _club.id IS NULL THEN
    RAISE EXCEPTION 'club_not_found';
  END IF;

  IF _club.owner_id <> _uid THEN
    RAISE EXCEPTION 'not_club_owner';
  END IF;

  SELECT *
  INTO _league
  FROM public.leagues
  WHERE id = _club.league_id;

  IF _league.id IS NULL THEN
    RAISE EXCEPTION 'league_not_found';
  END IF;

  IF _league.status <> 'setup' THEN
    RAISE EXCEPTION 'league_not_in_setup';
  END IF;

  SELECT *
  INTO _pack
  FROM public.initial_packs
  WHERE club_id = _club_id
  FOR UPDATE;

  IF _pack.id IS NULL THEN
    RAISE EXCEPTION 'pack_not_found';
  END IF;

  IF _pack.club_id <> _club_id THEN
    RAISE EXCEPTION 'pack_club_mismatch';
  END IF;

  IF _pack.opened_at IS NOT NULL THEN
    RAISE EXCEPTION 'pack_already_opened';
  END IF;

  -- Serialize only the global initial-pack distribution section.
  PERFORM pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtext('bagrefut'),
    pg_catalog.hashtext('initial_pack_distribution')
  );

  SELECT pg_catalog.count(*)
  INTO _available_count
  FROM public.players p
  WHERE NOT EXISTS (
    SELECT 1
    FROM public.club_players cp
    WHERE cp.player_id = p.id
  );

  IF _available_count < 10 THEN
    RAISE EXCEPTION 'not_enough_players_available';
  END IF;

  SELECT ARRAY(
    SELECT p.id
    FROM public.players p
    WHERE NOT EXISTS (
      SELECT 1
      FROM public.club_players cp
      WHERE cp.player_id = p.id
    )
    ORDER BY pg_catalog.random()
    LIMIT 10
    FOR UPDATE OF p SKIP LOCKED
  )
  INTO _picked_ids;

  IF COALESCE(pg_catalog.array_length(_picked_ids, 1), 0) <> 10 THEN
    RAISE EXCEPTION 'not_enough_players_available';
  END IF;

  INSERT INTO public.club_players (club_id, player_id)
  SELECT _club_id, picked.player_id
  FROM pg_catalog.unnest(_picked_ids) AS picked(player_id);

  GET DIAGNOSTICS _inserted_count = ROW_COUNT;
  IF _inserted_count <> 10 THEN
    RAISE EXCEPTION 'initial_pack_distribution_incomplete';
  END IF;

  INSERT INTO public.initial_pack_items (pack_id, player_id, slot)
  SELECT _pack.id, picked.player_id, picked.slot::smallint
  FROM pg_catalog.unnest(_picked_ids) WITH ORDINALITY AS picked(player_id, slot);

  GET DIAGNOSTICS _inserted_count = ROW_COUNT;
  IF _inserted_count <> 10 THEN
    RAISE EXCEPTION 'initial_pack_items_incomplete';
  END IF;

  UPDATE public.initial_packs
  SET opened_at = pg_catalog.now()
  WHERE id = _pack.id
    AND opened_at IS NULL
  RETURNING public.initial_packs.opened_at INTO _opened_at;

  IF _opened_at IS NULL THEN
    RAISE EXCEPTION 'pack_already_opened';
  END IF;

  RETURN QUERY
  SELECT
    _pack.id AS pack_id,
    _club_id AS club_id,
    _opened_at AS opened_at,
    ipi.player_id,
    ipi.slot
  FROM public.initial_pack_items ipi
  WHERE ipi.pack_id = _pack.id
  ORDER BY ipi.slot;
END;
$$;

REVOKE ALL ON FUNCTION public.open_initial_pack(uuid) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.open_initial_pack(uuid) TO authenticated;
