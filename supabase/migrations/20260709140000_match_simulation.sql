-- =====================================================================
-- BAGREFUT - Deterministic match simulation, snapshots, stats, and rewards
-- =====================================================================

ALTER TABLE public.matches
  ADD COLUMN IF NOT EXISTS simulation_version integer,
  ADD COLUMN IF NOT EXISTS simulation_seed text;

ALTER TABLE public.match_events
  ADD COLUMN IF NOT EXISTS event_index integer;

ALTER TABLE public.match_events
  DROP CONSTRAINT IF EXISTS match_events_minute_between_0_and_90;

ALTER TABLE public.match_events
  ADD CONSTRAINT match_events_minute_between_0_and_90
  CHECK (minute BETWEEN 0 AND 90);

CREATE UNIQUE INDEX IF NOT EXISTS idx_match_events_match_event_index_once
  ON public.match_events(match_id, event_index)
  WHERE event_index IS NOT NULL;

CREATE TABLE IF NOT EXISTS public.match_lineup_snapshots (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  match_id uuid NOT NULL REFERENCES public.matches(id) ON DELETE CASCADE,
  club_id uuid NOT NULL REFERENCES public.clubs(id) ON DELETE RESTRICT,
  club_player_id uuid NOT NULL REFERENCES public.club_players(id) ON DELETE RESTRICT,
  player_id uuid NOT NULL REFERENCES public.players(id) ON DELETE RESTRICT,
  lineup_origin text NOT NULL CHECK (lineup_origin IN ('manual','automatic')),
  formation public.formation NOT NULL,
  play_style public.play_style NOT NULL,
  natural_position public.player_position NOT NULL,
  used_position public.player_position NOT NULL,
  slot_index smallint NOT NULL CHECK (slot_index BETWEEN 1 AND 5),
  base_overall smallint NOT NULL CHECK (base_overall BETWEEN 1 AND 99),
  effective_overall smallint NOT NULL CHECK (effective_overall BETWEEN 1 AND 99),
  improvisation_penalty numeric(4,2) NOT NULL CHECK (improvisation_penalty BETWEEN 0 AND 1),
  attributes jsonb NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE (match_id, club_player_id),
  UNIQUE (match_id, club_id, used_position, slot_index)
);

CREATE INDEX IF NOT EXISTS idx_match_lineup_snapshots_match
  ON public.match_lineup_snapshots(match_id, club_id);

GRANT SELECT ON public.match_lineup_snapshots TO authenticated;
GRANT ALL ON public.match_lineup_snapshots TO service_role;
ALTER TABLE public.match_lineup_snapshots ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.match_lineup_snapshots FORCE ROW LEVEL SECURITY;

CREATE POLICY "match_lineup_snapshots_approved_read"
ON public.match_lineup_snapshots
FOR SELECT TO authenticated
USING (
  public.is_approved_user(auth.uid())
  AND EXISTS (
    SELECT 1
    FROM public.matches m
    WHERE m.id = match_lineup_snapshots.match_id
      AND m.status = 'finished'::public.match_status
  )
);

CREATE TABLE IF NOT EXISTS public.match_statistics (
  match_id uuid NOT NULL REFERENCES public.matches(id) ON DELETE CASCADE,
  club_id uuid NOT NULL REFERENCES public.clubs(id) ON DELETE RESTRICT,
  lineup_origin text NOT NULL CHECK (lineup_origin IN ('manual','automatic')),
  formation public.formation NOT NULL,
  play_style public.play_style NOT NULL,
  attack_strength numeric(6,2) NOT NULL CHECK (attack_strength BETWEEN 0 AND 100),
  defense_strength numeric(6,2) NOT NULL CHECK (defense_strength BETWEEN 0 AND 100),
  goalkeeper_strength numeric(6,2) NOT NULL CHECK (goalkeeper_strength BETWEEN 0 AND 100),
  overall_strength numeric(6,2) NOT NULL CHECK (overall_strength BETWEEN 0 AND 100),
  possession smallint NOT NULL DEFAULT 50 CHECK (possession BETWEEN 0 AND 100),
  chances smallint NOT NULL DEFAULT 0 CHECK (chances >= 0),
  shots smallint NOT NULL DEFAULT 0 CHECK (shots >= 0),
  shots_on_target smallint NOT NULL DEFAULT 0 CHECK (shots_on_target >= 0),
  saves smallint NOT NULL DEFAULT 0 CHECK (saves >= 0),
  goals smallint NOT NULL DEFAULT 0 CHECK (goals >= 0),
  created_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (match_id, club_id),
  CONSTRAINT match_statistics_consistency
    CHECK (chances >= shots AND shots >= shots_on_target AND shots_on_target >= goals)
);

GRANT SELECT ON public.match_statistics TO authenticated;
GRANT ALL ON public.match_statistics TO service_role;
ALTER TABLE public.match_statistics ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.match_statistics FORCE ROW LEVEL SECURITY;

CREATE POLICY "match_statistics_approved_read"
ON public.match_statistics
FOR SELECT TO authenticated
USING (
  public.is_approved_user(auth.uid())
  AND EXISTS (
    SELECT 1
    FROM public.matches m
    WHERE m.id = match_statistics.match_id
      AND m.status = 'finished'::public.match_status
  )
);

CREATE TABLE IF NOT EXISTS public.match_reward_config (
  id boolean PRIMARY KEY DEFAULT true CHECK (id),
  win_cents integer NOT NULL DEFAULT 75 CHECK (win_cents BETWEEN 0 AND 10000),
  draw_cents integer NOT NULL DEFAULT 25 CHECK (draw_cents BETWEEN 0 AND 10000),
  loss_cents integer NOT NULL DEFAULT 0 CHECK (loss_cents BETWEEN 0 AND 10000),
  updated_at timestamptz NOT NULL DEFAULT now()
);

INSERT INTO public.match_reward_config(id, win_cents, draw_cents, loss_cents)
VALUES (true, 75, 25, 0)
ON CONFLICT (id) DO NOTHING;

GRANT SELECT ON public.match_reward_config TO authenticated;
GRANT ALL ON public.match_reward_config TO service_role;
ALTER TABLE public.match_reward_config ENABLE ROW LEVEL SECURITY;

CREATE POLICY "match_reward_config_admin_read"
ON public.match_reward_config
FOR SELECT TO authenticated
USING (public.is_approved_user(auth.uid()) AND public.has_role(auth.uid(), 'admin'::public.app_role));

CREATE UNIQUE INDEX IF NOT EXISTS idx_wallet_match_reward_once
  ON public.wallet_transactions(club_id, reference_id, kind)
  WHERE kind = 'match_reward'::public.wallet_transaction_type
    AND reference_table = 'matches';

CREATE OR REPLACE FUNCTION public._match_sim_random(_seed text, _counter integer)
RETURNS numeric
LANGUAGE sql
IMMUTABLE
SECURITY DEFINER
SET search_path = ''
AS $$
  SELECT ((('x' || substr(md5(_seed || ':' || _counter::text), 1, 8))::bit(32)::bigint)::numeric / 4294967296.0)
$$;

REVOKE ALL ON FUNCTION public._match_sim_random(text, integer) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public._match_sim_random(text, integer) TO service_role;

CREATE OR REPLACE FUNCTION public._match_improvisation_multiplier(
  _natural public.player_position,
  _used public.player_position
)
RETURNS numeric
LANGUAGE sql
IMMUTABLE
SECURITY DEFINER
SET search_path = ''
AS $$
  SELECT CASE
    WHEN _natural = _used THEN 1.00
    WHEN _natural = 'GK'::public.player_position OR _used = 'GK'::public.player_position THEN 0.55
    WHEN (_natural = 'DEF'::public.player_position AND _used = 'MID'::public.player_position)
      OR (_natural = 'MID'::public.player_position AND _used IN ('DEF'::public.player_position, 'ATA'::public.player_position))
      OR (_natural = 'ATA'::public.player_position AND _used = 'MID'::public.player_position) THEN 0.85
    ELSE 0.70
  END
$$;

REVOKE ALL ON FUNCTION public._match_improvisation_multiplier(public.player_position, public.player_position) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public._match_improvisation_multiplier(public.player_position, public.player_position) TO service_role;

CREATE OR REPLACE FUNCTION public._match_formation_slots(_formation public.formation)
RETURNS TABLE(
  slot_order integer,
  slot_position public.player_position,
  slot_index smallint
)
LANGUAGE sql
IMMUTABLE
SECURITY DEFINER
SET search_path = ''
AS $$
  SELECT
    slots.slot_order,
    slots.slot_position,
    slots.slot_index
  FROM (
    VALUES
      ('1-2-1-1'::public.formation, 1, 'GK'::public.player_position, 1::smallint),
      ('1-2-1-1'::public.formation, 2, 'DEF'::public.player_position, 1::smallint),
      ('1-2-1-1'::public.formation, 3, 'DEF'::public.player_position, 2::smallint),
      ('1-2-1-1'::public.formation, 4, 'MID'::public.player_position, 1::smallint),
      ('1-2-1-1'::public.formation, 5, 'ATA'::public.player_position, 1::smallint),
      ('1-1-2-1'::public.formation, 1, 'GK'::public.player_position, 1::smallint),
      ('1-1-2-1'::public.formation, 2, 'DEF'::public.player_position, 1::smallint),
      ('1-1-2-1'::public.formation, 3, 'MID'::public.player_position, 1::smallint),
      ('1-1-2-1'::public.formation, 4, 'MID'::public.player_position, 2::smallint),
      ('1-1-2-1'::public.formation, 5, 'ATA'::public.player_position, 1::smallint),
      ('1-1-1-2'::public.formation, 1, 'GK'::public.player_position, 1::smallint),
      ('1-1-1-2'::public.formation, 2, 'DEF'::public.player_position, 1::smallint),
      ('1-1-1-2'::public.formation, 3, 'MID'::public.player_position, 1::smallint),
      ('1-1-1-2'::public.formation, 4, 'ATA'::public.player_position, 1::smallint),
      ('1-1-1-2'::public.formation, 5, 'ATA'::public.player_position, 2::smallint),
      ('0-2-2-1'::public.formation, 1, 'DEF'::public.player_position, 1::smallint),
      ('0-2-2-1'::public.formation, 2, 'DEF'::public.player_position, 2::smallint),
      ('0-2-2-1'::public.formation, 3, 'MID'::public.player_position, 1::smallint),
      ('0-2-2-1'::public.formation, 4, 'MID'::public.player_position, 2::smallint),
      ('0-2-2-1'::public.formation, 5, 'ATA'::public.player_position, 1::smallint)
  ) AS slots(formation, slot_order, slot_position, slot_index)
  WHERE slots.formation = _formation
  ORDER BY slots.slot_order
$$;

REVOKE ALL ON FUNCTION public._match_formation_slots(public.formation) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public._match_formation_slots(public.formation) TO service_role;

CREATE OR REPLACE FUNCTION public._match_formation_modifier(_formation public.formation, _key text)
RETURNS numeric
LANGUAGE sql
IMMUTABLE
SECURITY DEFINER
SET search_path = ''
AS $$
  SELECT CASE _formation
    WHEN '1-2-1-1'::public.formation THEN
      CASE _key WHEN 'attack' THEN 0.98 WHEN 'defense' THEN 1.08 WHEN 'chance' THEN 0.96 WHEN 'exposure' THEN 0.88 ELSE 1 END
    WHEN '1-1-2-1'::public.formation THEN
      CASE _key WHEN 'attack' THEN 1.02 WHEN 'defense' THEN 0.99 WHEN 'chance' THEN 1.08 WHEN 'exposure' THEN 1.00 ELSE 1 END
    WHEN '1-1-1-2'::public.formation THEN
      CASE _key WHEN 'attack' THEN 1.10 WHEN 'defense' THEN 0.92 WHEN 'chance' THEN 1.06 WHEN 'exposure' THEN 1.12 ELSE 1 END
    WHEN '0-2-2-1'::public.formation THEN
      CASE _key WHEN 'attack' THEN 1.05 WHEN 'defense' THEN 0.94 WHEN 'chance' THEN 1.10 WHEN 'exposure' THEN 1.20 ELSE 1 END
  END
$$;

REVOKE ALL ON FUNCTION public._match_formation_modifier(public.formation, text) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public._match_formation_modifier(public.formation, text) TO service_role;

CREATE OR REPLACE FUNCTION public._match_style_modifier(_style public.play_style, _key text)
RETURNS numeric
LANGUAGE sql
IMMUTABLE
SECURITY DEFINER
SET search_path = ''
AS $$
  SELECT CASE _style
    WHEN 'offensive'::public.play_style THEN CASE _key WHEN 'attack' THEN 1.10 WHEN 'defense' THEN 0.90 ELSE 1 END
    WHEN 'defensive'::public.play_style THEN CASE _key WHEN 'attack' THEN 0.90 WHEN 'defense' THEN 1.10 ELSE 1 END
    ELSE 1.00
  END
$$;

REVOKE ALL ON FUNCTION public._match_style_modifier(public.play_style, text) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public._match_style_modifier(public.play_style, text) TO service_role;

CREATE OR REPLACE FUNCTION public._match_clamp(_value numeric, _min numeric, _max numeric)
RETURNS numeric
LANGUAGE sql
IMMUTABLE
SECURITY DEFINER
SET search_path = ''
AS $$
  SELECT LEAST(_max, GREATEST(_min, _value))
$$;

REVOKE ALL ON FUNCTION public._match_clamp(numeric, numeric, numeric) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public._match_clamp(numeric, numeric, numeric) TO service_role;

CREATE OR REPLACE FUNCTION public._match_strength(_match_id uuid, _club_id uuid)
RETURNS TABLE(
  attack_strength numeric,
  defense_strength numeric,
  goalkeeper_strength numeric,
  overall_strength numeric
)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
  WITH snapshot AS (
    SELECT
      s.*,
      CASE s.used_position
        WHEN 'GK'::public.player_position THEN 0.05
        WHEN 'DEF'::public.player_position THEN 0.35
        WHEN 'MID'::public.player_position THEN 0.90
        WHEN 'ATA'::public.player_position THEN 1.15
      END AS attack_weight,
      CASE s.used_position
        WHEN 'GK'::public.player_position THEN 0.10
        WHEN 'DEF'::public.player_position THEN 1.15
        WHEN 'MID'::public.player_position THEN 0.70
        WHEN 'ATA'::public.player_position THEN 0.25
      END AS defense_weight,
      (
        ((s.attributes->>'finishing')::numeric * 0.34)
        + ((s.attributes->>'passing')::numeric * 0.24)
        + ((s.attributes->>'dribbling')::numeric * 0.22)
        + ((s.attributes->>'velocity')::numeric * 0.20)
      ) * 0.58 + s.effective_overall * 0.42 AS attack_value,
      (
        ((s.attributes->>'defending')::numeric * 0.42)
        + ((s.attributes->>'physical')::numeric * 0.26)
        + ((s.attributes->>'velocity')::numeric * 0.16)
        + ((s.attributes->>'passing')::numeric * 0.16)
      ) * 0.58 + s.effective_overall * 0.42 AS defense_value
    FROM public.match_lineup_snapshots s
    WHERE s.match_id = _match_id
      AND s.club_id = _club_id
  ),
  grouped AS (
    SELECT
      max(formation) AS formation,
      max(play_style) AS play_style,
      sum(attack_value * attack_weight) / nullif(sum(attack_weight), 0) AS attack_base,
      sum(defense_value * defense_weight) / nullif(sum(defense_weight), 0) AS defense_base,
      coalesce(max(
        CASE WHEN used_position = 'GK'::public.player_position
          THEN ((attributes->>'goalkeeping')::numeric * 0.65 + effective_overall * 0.35)
        END
      ), 35) AS goalkeeper_base
    FROM snapshot
  ),
  strengths AS (
    SELECT
      public._match_clamp(
        round((attack_base * public._match_formation_modifier(formation, 'attack') * public._match_style_modifier(play_style, 'attack'))::numeric, 2),
        1,
        100
      ) AS attack_strength,
      public._match_clamp(
        round((defense_base * public._match_formation_modifier(formation, 'defense') * public._match_style_modifier(play_style, 'defense'))::numeric, 2),
        1,
        100
      ) AS defense_strength,
      public._match_clamp(round(goalkeeper_base::numeric, 2), 0, 100) AS goalkeeper_strength
    FROM grouped
  )
  SELECT
    attack_strength,
    defense_strength,
    goalkeeper_strength,
    public._match_clamp(round((attack_strength * 0.42 + defense_strength * 0.42 + goalkeeper_strength * 0.16)::numeric, 2), 1, 100)
  FROM strengths
$$;

REVOKE ALL ON FUNCTION public._match_strength(uuid, uuid) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public._match_strength(uuid, uuid) TO service_role;

CREATE OR REPLACE FUNCTION public._match_insert_event(
  _match_id uuid,
  _event_index integer,
  _minute integer,
  _event_type public.match_event_type,
  _club_id uuid,
  _player_id uuid,
  _home_goals integer,
  _away_goals integer,
  _meta jsonb
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
BEGIN
  INSERT INTO public.match_events(
    match_id,
    event_index,
    minute,
    reveal_at,
    event_type,
    club_id,
    player_id,
    meta
  )
  VALUES (
    _match_id,
    _event_index,
    _minute::smallint,
    pg_catalog.now(),
    _event_type,
    _club_id,
    _player_id,
    coalesce(_meta, '{}'::jsonb)
      || jsonb_build_object('home_goals', _home_goals, 'away_goals', _away_goals)
  );
END;
$$;

REVOKE ALL ON FUNCTION public._match_insert_event(uuid, integer, integer, public.match_event_type, uuid, uuid, integer, integer, jsonb) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public._match_insert_event(uuid, integer, integer, public.match_event_type, uuid, uuid, integer, integer, jsonb) TO service_role;

CREATE OR REPLACE FUNCTION public._match_result_json(_match_id uuid)
RETURNS jsonb
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
  SELECT jsonb_build_object(
    'match_id', m.id,
    'status', m.status,
    'home_goals', m.home_goals,
    'away_goals', m.away_goals,
    'simulation_version', m.simulation_version,
    'event_count', (SELECT count(*) FROM public.match_events e WHERE e.match_id = m.id),
    'snapshot_count', (SELECT count(*) FROM public.match_lineup_snapshots s WHERE s.match_id = m.id),
    'statistics', (
      SELECT coalesce(jsonb_agg(to_jsonb(ms) ORDER BY ms.club_id), '[]'::jsonb)
      FROM public.match_statistics ms
      WHERE ms.match_id = m.id
    ),
    'idempotent', m.status = 'finished'::public.match_status
  )
  FROM public.matches m
  WHERE m.id = _match_id
$$;

REVOKE ALL ON FUNCTION public._match_result_json(uuid) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public._match_result_json(uuid) TO service_role;

CREATE OR REPLACE FUNCTION public._match_credit_reward(
  _club_id uuid,
  _match_id uuid,
  _goals_for integer,
  _goals_against integer
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  _config public.match_reward_config%ROWTYPE;
  _reward integer;
  _balance integer;
BEGIN
  SELECT * INTO _config
  FROM public.match_reward_config
  WHERE id = true;

  IF _config.id IS NULL THEN
    RAISE EXCEPTION 'match_reward_config_missing';
  END IF;

  _reward := CASE
    WHEN _goals_for > _goals_against THEN _config.win_cents
    WHEN _goals_for = _goals_against THEN _config.draw_cents
    ELSE _config.loss_cents
  END;

  IF EXISTS (
    SELECT 1
    FROM public.wallet_transactions wt
    WHERE wt.club_id = _club_id
      AND wt.kind = 'match_reward'::public.wallet_transaction_type
      AND wt.reference_table = 'matches'
      AND wt.reference_id = _match_id
  ) THEN
    RETURN;
  END IF;

  IF _reward > 0 THEN
    PERFORM public._credit_wallet(
      _club_id,
      _reward,
      'match_reward'::public.wallet_transaction_type,
      'matches',
      _match_id,
      'premiacao da partida'
    );
  ELSE
    SELECT balance_cents INTO _balance
    FROM public.clubs
    WHERE id = _club_id
    FOR UPDATE;

    INSERT INTO public.wallet_transactions(
      club_id,
      amount_cents,
      balance_after_cents,
      kind,
      reference_table,
      reference_id,
      memo
    )
    VALUES (
      _club_id,
      0,
      _balance,
      'match_reward'::public.wallet_transaction_type,
      'matches',
      _match_id,
      'premiacao da partida'
    );
  END IF;
END;
$$;

REVOKE ALL ON FUNCTION public._match_credit_reward(uuid, uuid, integer, integer) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public._match_credit_reward(uuid, uuid, integer, integer) TO service_role;

CREATE OR REPLACE FUNCTION public.simulate_match(_match_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  _admin_id uuid := public._assert_approved_admin();
  _match public.matches%ROWTYPE;
  _round public.rounds%ROWTYPE;
  _season public.seasons%ROWTYPE;
  _seed text;
  _club_id uuid;
  _side text;
  _lineup public.lineups%ROWTYPE;
  _manual_valid boolean;
  _formation public.formation;
  _style public.play_style;
  _origin text;
  _slot record;
  _picked record;
  _event_index integer := 1;
  _roll_index integer := 1;
  _home_attack numeric;
  _home_defense numeric;
  _home_goalkeeper numeric;
  _home_overall numeric;
  _away_attack numeric;
  _away_defense numeric;
  _away_goalkeeper numeric;
  _away_overall numeric;
  _home_possession integer;
  _home_chances integer;
  _away_chances integer;
  _chance record;
  _shot_probability numeric;
  _blocked_probability numeric;
  _target_probability numeric;
  _goal_probability numeric;
  _player_id uuid;
  _home_goals integer := 0;
  _away_goals integer := 0;
  _home_stats jsonb := '{"chances":0,"shots":0,"shots_on_target":0,"saves":0,"goals":0}'::jsonb;
  _away_stats jsonb := '{"chances":0,"shots":0,"shots_on_target":0,"saves":0,"goals":0}'::jsonb;
  _halftime_inserted boolean := false;
  _pending_events integer;
BEGIN
  IF _match_id IS NULL THEN
    RAISE EXCEPTION 'match_not_found';
  END IF;

  SELECT * INTO _match
  FROM public.matches
  WHERE id = _match_id
  FOR UPDATE;

  IF _match.id IS NULL THEN
    RAISE EXCEPTION 'match_not_found';
  END IF;

  IF _match.status = 'finished'::public.match_status THEN
    RETURN public._match_result_json(_match.id);
  END IF;

  IF _match.status NOT IN ('scheduled'::public.match_status, 'live'::public.match_status) THEN
    RAISE EXCEPTION 'match_not_simulable';
  END IF;

  SELECT * INTO _round
  FROM public.rounds
  WHERE id = _match.round_id
  FOR UPDATE;

  IF _round.id IS NULL THEN
    RAISE EXCEPTION 'round_not_found';
  END IF;

  SELECT * INTO _season
  FROM public.seasons
  WHERE id = _round.season_id
  FOR UPDATE;

  IF _season.id IS NULL THEN
    RAISE EXCEPTION 'season_not_found';
  END IF;

  IF _season.status <> 'active' THEN
    RAISE EXCEPTION 'season_not_active';
  END IF;

  SELECT count(*) INTO _pending_events
  FROM public.match_events
  WHERE match_id = _match.id;

  IF _pending_events > 0
     OR EXISTS (SELECT 1 FROM public.match_lineup_snapshots WHERE match_id = _match.id)
     OR EXISTS (SELECT 1 FROM public.match_statistics WHERE match_id = _match.id) THEN
    RAISE EXCEPTION 'match_partial_simulation_state';
  END IF;

  _seed := _season.id::text || ':' || _round.id::text || ':' || _match.id::text || ':1';

  DROP TABLE IF EXISTS pg_temp.match_sim_used_cards;
  CREATE TEMP TABLE pg_temp.match_sim_used_cards(
    club_player_id uuid PRIMARY KEY
  ) ON COMMIT DROP;

  DROP TABLE IF EXISTS pg_temp.match_sim_chances;
  CREATE TEMP TABLE pg_temp.match_sim_chances(
    side text NOT NULL,
    minute integer NOT NULL,
    order_key integer NOT NULL
  ) ON COMMIT DROP;

  FOREACH _club_id IN ARRAY ARRAY[_match.home_club_id, _match.away_club_id] LOOP
    _side := CASE WHEN _club_id = _match.home_club_id THEN 'home' ELSE 'away' END;

    SELECT * INTO _lineup
    FROM public.lineups l
    WHERE l.club_id = _club_id
      AND l.round_id = _round.id
    FOR UPDATE;

    _manual_valid := false;
    IF _lineup.id IS NOT NULL AND _lineup.updated_at <= _round.lineup_lock_at THEN
      SELECT
        count(*) = 5
        AND count(DISTINCT lp.club_player_id) = 5
        AND count(*) FILTER (WHERE lp.is_starter) = 5
        AND NOT EXISTS (
          SELECT 1
          FROM public._match_formation_slots(_lineup.formation) slots
          LEFT JOIN public.lineup_players check_lp
            ON check_lp.lineup_id = _lineup.id
           AND check_lp.is_starter
           AND check_lp.slot_position = slots.slot_position
           AND check_lp.slot_index = slots.slot_index
          WHERE check_lp.id IS NULL
        )
        AND NOT EXISTS (
          SELECT 1
          FROM public.lineup_players owned_lp
          JOIN public.club_players owned_cp ON owned_cp.id = owned_lp.club_player_id
          WHERE owned_lp.lineup_id = _lineup.id
            AND owned_lp.is_starter
            AND owned_cp.club_id <> _club_id
        )
      INTO _manual_valid
      FROM public.lineup_players lp
      WHERE lp.lineup_id = _lineup.id
        AND lp.is_starter;
    END IF;

    IF _manual_valid THEN
      _formation := _lineup.formation;
      _style := _lineup.play_style;
      _origin := 'manual';

      INSERT INTO public.match_lineup_snapshots(
        match_id,
        club_id,
        club_player_id,
        player_id,
        lineup_origin,
        formation,
        play_style,
        natural_position,
        used_position,
        slot_index,
        base_overall,
        effective_overall,
        improvisation_penalty,
        attributes
      )
      SELECT
        _match.id,
        _club_id,
        cp.id,
        p.id,
        _origin,
        _formation,
        _style,
        p.position,
        lp.slot_position,
        lp.slot_index,
        p.overall,
        round((p.overall::numeric * public._match_improvisation_multiplier(p.position, lp.slot_position)))::smallint,
        round((1 - public._match_improvisation_multiplier(p.position, lp.slot_position))::numeric, 2),
        jsonb_build_object(
          'velocity', p.velocity,
          'finishing', p.finishing,
          'passing', p.passing,
          'dribbling', p.dribbling,
          'defending', p.defending,
          'physical', p.physical,
          'goalkeeping', p.goalkeeping
        )
      FROM public.lineup_players lp
      JOIN public.club_players cp ON cp.id = lp.club_player_id
      JOIN public.players p ON p.id = cp.player_id
      WHERE lp.lineup_id = _lineup.id
        AND lp.is_starter
      ORDER BY lp.slot_position, lp.slot_index;
    ELSE
      _formation := '1-2-1-1'::public.formation;
      _style := 'balanced'::public.play_style;
      _origin := 'automatic';

      DELETE FROM pg_temp.match_sim_used_cards;

      FOR _slot IN SELECT * FROM public._match_formation_slots(_formation) LOOP
        SELECT
          cp.id AS club_player_id,
          p.id AS player_id,
          p.position AS natural_position,
          p.overall AS base_overall,
          public._match_improvisation_multiplier(p.position, _slot.slot_position) AS multiplier,
          round((1 - public._match_improvisation_multiplier(p.position, _slot.slot_position))::numeric, 2) AS penalty,
          round((p.overall::numeric * public._match_improvisation_multiplier(p.position, _slot.slot_position)))::smallint AS effective_overall,
          jsonb_build_object(
            'velocity', p.velocity,
            'finishing', p.finishing,
            'passing', p.passing,
            'dribbling', p.dribbling,
            'defending', p.defending,
            'physical', p.physical,
            'goalkeeping', p.goalkeeping
          ) AS attributes
        INTO _picked
        FROM public.club_players cp
        JOIN public.players p ON p.id = cp.player_id
        WHERE cp.club_id = _club_id
          AND NOT cp.is_reserved
          AND NOT EXISTS (
            SELECT 1 FROM pg_temp.match_sim_used_cards used WHERE used.club_player_id = cp.id
          )
          AND NOT EXISTS (
            SELECT 1 FROM public.market_listings ml WHERE ml.club_player_id = cp.id AND ml.status = 'open'::public.market_listing_status
          )
          AND NOT EXISTS (
            SELECT 1
            FROM public.transfer_offer_items toi
            JOIN public.transfer_offers offer ON offer.id = toi.offer_id
            WHERE toi.club_player_id = cp.id
              AND offer.status = 'pending'::public.transfer_offer_status
              AND offer.expires_at > pg_catalog.now()
          )
        ORDER BY
          (p.position = _slot.slot_position) DESC,
          round((1 - public._match_improvisation_multiplier(p.position, _slot.slot_position))::numeric, 2) ASC,
          round((p.overall::numeric * public._match_improvisation_multiplier(p.position, _slot.slot_position))) DESC,
          p.overall DESC,
          cp.id ASC
        LIMIT 1;

        IF _picked.club_player_id IS NULL THEN
          RAISE EXCEPTION 'lineup_auto_insufficient_players';
        END IF;

        INSERT INTO pg_temp.match_sim_used_cards(club_player_id) VALUES (_picked.club_player_id);

        INSERT INTO public.match_lineup_snapshots(
          match_id,
          club_id,
          club_player_id,
          player_id,
          lineup_origin,
          formation,
          play_style,
          natural_position,
          used_position,
          slot_index,
          base_overall,
          effective_overall,
          improvisation_penalty,
          attributes
        )
        VALUES (
          _match.id,
          _club_id,
          _picked.club_player_id,
          _picked.player_id,
          _origin,
          _formation,
          _style,
          _picked.natural_position,
          _slot.slot_position,
          _slot.slot_index,
          _picked.base_overall,
          _picked.effective_overall,
          _picked.penalty,
          _picked.attributes
        );
      END LOOP;
    END IF;

    INSERT INTO public.match_statistics(
      match_id,
      club_id,
      lineup_origin,
      formation,
      play_style,
      attack_strength,
      defense_strength,
      goalkeeper_strength,
      overall_strength
    )
    SELECT
      _match.id,
      _club_id,
      max(s.lineup_origin),
      max(s.formation),
      max(s.play_style),
      strength.attack_strength,
      strength.defense_strength,
      strength.goalkeeper_strength,
      strength.overall_strength
    FROM public.match_lineup_snapshots s
    CROSS JOIN public._match_strength(_match.id, _club_id) strength
    WHERE s.match_id = _match.id
      AND s.club_id = _club_id
    GROUP BY strength.attack_strength, strength.defense_strength, strength.goalkeeper_strength, strength.overall_strength;
  END LOOP;

  SELECT attack_strength, defense_strength, goalkeeper_strength, overall_strength
  INTO _home_attack, _home_defense, _home_goalkeeper, _home_overall
  FROM public.match_statistics
  WHERE match_id = _match.id
    AND club_id = _match.home_club_id;

  SELECT attack_strength, defense_strength, goalkeeper_strength, overall_strength
  INTO _away_attack, _away_defense, _away_goalkeeper, _away_overall
  FROM public.match_statistics
  WHERE match_id = _match.id
    AND club_id = _match.away_club_id;

  _home_possession := public._match_clamp(round(50 + ((_home_overall - _away_overall) * 0.35)), 35, 65)::integer;

  UPDATE public.match_statistics
  SET possession = CASE WHEN club_id = _match.home_club_id THEN _home_possession ELSE 100 - _home_possession END
  WHERE match_id = _match.id;

  SELECT public._match_clamp(round(
    9.4
    + ((_home_attack - _away_defense) / 8)
    + ((public._match_style_modifier((SELECT play_style FROM public.match_statistics WHERE match_id = _match.id AND club_id = _match.home_club_id), 'attack') - 1) * 4)
    + ((public._match_formation_modifier((SELECT formation FROM public.match_statistics WHERE match_id = _match.id AND club_id = _match.home_club_id), 'chance') - 1) * 7)
    + ((public._match_formation_modifier((SELECT formation FROM public.match_statistics WHERE match_id = _match.id AND club_id = _match.away_club_id), 'exposure') - 1) * 5)
    + ((public._match_sim_random(_seed, _roll_index) - 0.5) * 4.2)
    + ((public._match_sim_random(_seed, _roll_index + 1) - 0.5) * 2.6)
  ), 4, 18)::integer INTO _home_chances;
  _roll_index := _roll_index + 2;

  SELECT public._match_clamp(round(
    9.4
    + ((_away_attack - _home_defense) / 8)
    + ((public._match_style_modifier((SELECT play_style FROM public.match_statistics WHERE match_id = _match.id AND club_id = _match.away_club_id), 'attack') - 1) * 4)
    + ((public._match_formation_modifier((SELECT formation FROM public.match_statistics WHERE match_id = _match.id AND club_id = _match.away_club_id), 'chance') - 1) * 7)
    + ((public._match_formation_modifier((SELECT formation FROM public.match_statistics WHERE match_id = _match.id AND club_id = _match.home_club_id), 'exposure') - 1) * 5)
    + ((public._match_sim_random(_seed, _roll_index) - 0.5) * 4.2)
    + ((public._match_sim_random(_seed, _roll_index + 1) - 0.5) * 2.6)
  ), 4, 18)::integer INTO _away_chances;
  _roll_index := _roll_index + 2;

  FOR _slot IN SELECT generate_series(1, _home_chances) AS chance_index LOOP
    INSERT INTO pg_temp.match_sim_chances(side, minute, order_key)
    VALUES ('home', public._match_clamp(1 + floor(public._match_sim_random(_seed, _roll_index) * 88), 1, 89)::integer, _roll_index);
    _roll_index := _roll_index + 1;
  END LOOP;

  FOR _slot IN SELECT generate_series(1, _away_chances) AS chance_index LOOP
    INSERT INTO pg_temp.match_sim_chances(side, minute, order_key)
    VALUES ('away', public._match_clamp(1 + floor(public._match_sim_random(_seed, _roll_index) * 88), 1, 89)::integer, _roll_index);
    _roll_index := _roll_index + 1;
  END LOOP;

  PERFORM public._match_insert_event(_match.id, _event_index, 0, 'match_started', NULL, NULL, _home_goals, _away_goals, '{}'::jsonb);
  _event_index := _event_index + 1;

  FOR _chance IN
    SELECT *
    FROM pg_temp.match_sim_chances
    ORDER BY minute, side, order_key
  LOOP
    IF _chance.minute > 45 AND NOT _halftime_inserted THEN
      PERFORM public._match_insert_event(_match.id, _event_index, 45, 'halftime', NULL, NULL, _home_goals, _away_goals, '{}'::jsonb);
      _event_index := _event_index + 1;
      _halftime_inserted := true;
    END IF;

    SELECT player_id INTO _player_id
    FROM public.match_lineup_snapshots
    WHERE match_id = _match.id
      AND club_id = CASE WHEN _chance.side = 'home' THEN _match.home_club_id ELSE _match.away_club_id END
    ORDER BY
      CASE used_position
        WHEN 'ATA'::public.player_position THEN 1
        WHEN 'MID'::public.player_position THEN 2
        WHEN 'DEF'::public.player_position THEN 3
        ELSE 4
      END,
      public._match_sim_random(_seed, _roll_index),
      player_id
    LIMIT 1;
    _roll_index := _roll_index + 1;

    IF _chance.side = 'home' THEN
      _home_stats := jsonb_set(_home_stats, '{chances}', to_jsonb((_home_stats->>'chances')::integer + 1));
      _shot_probability := public._match_clamp(0.70 + ((_home_attack - _away_defense) / 220), 0.46, 0.90);
      _blocked_probability := public._match_clamp(0.08 + (_away_defense / 800), 0.08, 0.22);
      _target_probability := public._match_clamp(0.66 + ((_home_attack - _away_defense) / 220), 0.40, 0.88);
      _goal_probability := public._match_clamp(0.50 + ((_home_attack - _away_goalkeeper) / 230), 0.18, 0.70);
    ELSE
      _away_stats := jsonb_set(_away_stats, '{chances}', to_jsonb((_away_stats->>'chances')::integer + 1));
      _shot_probability := public._match_clamp(0.70 + ((_away_attack - _home_defense) / 220), 0.46, 0.90);
      _blocked_probability := public._match_clamp(0.08 + (_home_defense / 800), 0.08, 0.22);
      _target_probability := public._match_clamp(0.66 + ((_away_attack - _home_defense) / 220), 0.40, 0.88);
      _goal_probability := public._match_clamp(0.50 + ((_away_attack - _home_goalkeeper) / 230), 0.18, 0.70);
    END IF;

    PERFORM public._match_insert_event(
      _match.id,
      _event_index,
      _chance.minute,
      'chance',
      CASE WHEN _chance.side = 'home' THEN _match.home_club_id ELSE _match.away_club_id END,
      _player_id,
      _home_goals,
      _away_goals,
      '{}'::jsonb
    );
    _event_index := _event_index + 1;

    IF public._match_sim_random(_seed, _roll_index) > _shot_probability THEN
      _roll_index := _roll_index + 1;
      CONTINUE;
    END IF;
    _roll_index := _roll_index + 1;

    IF _chance.side = 'home' THEN
      _home_stats := jsonb_set(_home_stats, '{shots}', to_jsonb((_home_stats->>'shots')::integer + 1));
    ELSE
      _away_stats := jsonb_set(_away_stats, '{shots}', to_jsonb((_away_stats->>'shots')::integer + 1));
    END IF;

    IF public._match_sim_random(_seed, _roll_index) < _blocked_probability THEN
      _roll_index := _roll_index + 1;
      PERFORM public._match_insert_event(
        _match.id,
        _event_index,
        _chance.minute,
        'shot',
        CASE WHEN _chance.side = 'home' THEN _match.home_club_id ELSE _match.away_club_id END,
        _player_id,
        _home_goals,
        _away_goals,
        '{"blocked":true}'::jsonb
      );
      _event_index := _event_index + 1;
      CONTINUE;
    END IF;
    _roll_index := _roll_index + 1;

    PERFORM public._match_insert_event(
      _match.id,
      _event_index,
      _chance.minute,
      'shot',
      CASE WHEN _chance.side = 'home' THEN _match.home_club_id ELSE _match.away_club_id END,
      _player_id,
      _home_goals,
      _away_goals,
      '{"blocked":false}'::jsonb
    );
    _event_index := _event_index + 1;

    IF public._match_sim_random(_seed, _roll_index) > _target_probability THEN
      _roll_index := _roll_index + 1;
      CONTINUE;
    END IF;
    _roll_index := _roll_index + 1;

    IF _chance.side = 'home' THEN
      _home_stats := jsonb_set(_home_stats, '{shots_on_target}', to_jsonb((_home_stats->>'shots_on_target')::integer + 1));
    ELSE
      _away_stats := jsonb_set(_away_stats, '{shots_on_target}', to_jsonb((_away_stats->>'shots_on_target')::integer + 1));
    END IF;

    IF public._match_sim_random(_seed, _roll_index) < _goal_probability THEN
      _roll_index := _roll_index + 1;
      IF _chance.side = 'home' THEN
        _home_goals := _home_goals + 1;
        _home_stats := jsonb_set(_home_stats, '{goals}', to_jsonb((_home_stats->>'goals')::integer + 1));
      ELSE
        _away_goals := _away_goals + 1;
        _away_stats := jsonb_set(_away_stats, '{goals}', to_jsonb((_away_stats->>'goals')::integer + 1));
      END IF;

      PERFORM public._match_insert_event(
        _match.id,
        _event_index,
        _chance.minute,
        'goal',
        CASE WHEN _chance.side = 'home' THEN _match.home_club_id ELSE _match.away_club_id END,
        _player_id,
        _home_goals,
        _away_goals,
        '{}'::jsonb
      );
      _event_index := _event_index + 1;
    ELSE
      _roll_index := _roll_index + 1;
      IF _chance.side = 'home' THEN
        _away_stats := jsonb_set(_away_stats, '{saves}', to_jsonb((_away_stats->>'saves')::integer + 1));
      ELSE
        _home_stats := jsonb_set(_home_stats, '{saves}', to_jsonb((_home_stats->>'saves')::integer + 1));
      END IF;

      PERFORM public._match_insert_event(
        _match.id,
        _event_index,
        _chance.minute,
        'save',
        CASE WHEN _chance.side = 'home' THEN _match.home_club_id ELSE _match.away_club_id END,
        _player_id,
        _home_goals,
        _away_goals,
        '{}'::jsonb
      );
      _event_index := _event_index + 1;
    END IF;
  END LOOP;

  IF NOT _halftime_inserted THEN
    PERFORM public._match_insert_event(_match.id, _event_index, 45, 'halftime', NULL, NULL, _home_goals, _away_goals, '{}'::jsonb);
    _event_index := _event_index + 1;
  END IF;

  PERFORM public._match_insert_event(_match.id, _event_index, 90, 'match_finished', NULL, NULL, _home_goals, _away_goals, '{}'::jsonb);

  UPDATE public.match_statistics
  SET chances = CASE WHEN club_id = _match.home_club_id THEN (_home_stats->>'chances')::integer ELSE (_away_stats->>'chances')::integer END,
      shots = CASE WHEN club_id = _match.home_club_id THEN (_home_stats->>'shots')::integer ELSE (_away_stats->>'shots')::integer END,
      shots_on_target = CASE WHEN club_id = _match.home_club_id THEN (_home_stats->>'shots_on_target')::integer ELSE (_away_stats->>'shots_on_target')::integer END,
      saves = CASE WHEN club_id = _match.home_club_id THEN (_home_stats->>'saves')::integer ELSE (_away_stats->>'saves')::integer END,
      goals = CASE WHEN club_id = _match.home_club_id THEN _home_goals ELSE _away_goals END
  WHERE match_id = _match.id;

  UPDATE public.matches
  SET home_goals = _home_goals::smallint,
      away_goals = _away_goals::smallint,
      status = 'finished'::public.match_status,
      simulated_at = pg_catalog.now(),
      seed = abs(('x' || substr(md5(_seed), 1, 15))::bit(60)::bigint),
      simulation_seed = _seed,
      simulation_version = 1
  WHERE id = _match.id;

  PERFORM public._match_credit_reward(_match.home_club_id, _match.id, _home_goals, _away_goals);
  PERFORM public._match_credit_reward(_match.away_club_id, _match.id, _away_goals, _home_goals);

  IF NOT EXISTS (
    SELECT 1
    FROM public.matches pending
    WHERE pending.round_id = _round.id
      AND pending.status <> 'finished'::public.match_status
  ) THEN
    UPDATE public.rounds
    SET is_processed = true
    WHERE id = _round.id;
  END IF;

  INSERT INTO public.admin_audit_logs(admin_id, action, target_table, target_id, payload)
  VALUES (
    _admin_id,
    'simulate_match',
    'matches',
    _match.id,
    jsonb_build_object(
      'round_id', _round.id,
      'season_id', _season.id,
      'simulation_version', 1,
      'home_goals', _home_goals,
      'away_goals', _away_goals
    )
  );

  RETURN public._match_result_json(_match.id);
END;
$$;

REVOKE ALL ON FUNCTION public.simulate_match(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.simulate_match(uuid) TO authenticated;

CREATE OR REPLACE FUNCTION public.simulate_round(_round_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  _admin_id uuid := public._assert_approved_admin();
  _round public.rounds%ROWTYPE;
  _match record;
  _results jsonb := '[]'::jsonb;
  _simulated_count integer := 0;
  _skipped_count integer := 0;
  _result jsonb;
BEGIN
  SELECT * INTO _round
  FROM public.rounds
  WHERE id = _round_id
  FOR UPDATE;

  IF _round.id IS NULL THEN
    RAISE EXCEPTION 'round_not_found';
  END IF;

  IF NOT EXISTS (
    SELECT 1
    FROM public.seasons s
    WHERE s.id = _round.season_id
      AND s.status = 'active'
  ) THEN
    RAISE EXCEPTION 'season_not_active';
  END IF;

  FOR _match IN
    SELECT m.id, m.status
    FROM public.matches m
    WHERE m.round_id = _round.id
    ORDER BY m.scheduled_at NULLS LAST, m.created_at, m.id
  LOOP
    IF _match.status = 'finished'::public.match_status THEN
      _skipped_count := _skipped_count + 1;
      _results := _results || jsonb_build_array(public._match_result_json(_match.id));
    ELSE
      SELECT public.simulate_match(_match.id) INTO _result;
      _simulated_count := _simulated_count + 1;
      _results := _results || jsonb_build_array(_result);
    END IF;
  END LOOP;

  IF NOT EXISTS (
    SELECT 1
    FROM public.matches pending
    WHERE pending.round_id = _round.id
      AND pending.status <> 'finished'::public.match_status
  ) THEN
    UPDATE public.rounds
    SET is_processed = true
    WHERE id = _round.id;
  END IF;

  INSERT INTO public.admin_audit_logs(admin_id, action, target_table, target_id, payload)
  VALUES (
    _admin_id,
    'simulate_round',
    'rounds',
    _round.id,
    jsonb_build_object('simulated_count', _simulated_count, 'skipped_count', _skipped_count)
  );

  RETURN jsonb_build_object(
    'round_id', _round.id,
    'simulated_count', _simulated_count,
    'skipped_count', _skipped_count,
    'matches', _results
  );
END;
$$;

REVOKE ALL ON FUNCTION public.simulate_round(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.simulate_round(uuid) TO authenticated;

CREATE OR REPLACE FUNCTION public.get_match_public_details(_match_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  _summary jsonb;
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'unauthenticated';
  END IF;
  IF NOT public.is_approved_user(auth.uid()) THEN
    RAISE EXCEPTION 'profile_not_approved';
  END IF;

  SELECT to_jsonb(summary)
  INTO _summary
  FROM public.list_match_score_summaries(_match_id) summary
  LIMIT 1;

  IF _summary IS NULL THEN
    RAISE EXCEPTION 'match_not_found';
  END IF;

  RETURN _summary || jsonb_build_object(
    'statistics', (
      SELECT coalesce(jsonb_agg(to_jsonb(ms) ORDER BY ms.club_id), '[]'::jsonb)
      FROM public.match_statistics ms
      WHERE ms.match_id = _match_id
    ),
    'lineups', (
      SELECT coalesce(jsonb_agg(jsonb_build_object(
        'club_id', s.club_id,
        'formation', s.formation,
        'play_style', s.play_style,
        'lineup_origin', s.lineup_origin,
        'used_position', s.used_position,
        'slot_index', s.slot_index,
        'player_id', s.player_id,
        'natural_position', s.natural_position,
        'base_overall', s.base_overall,
        'effective_overall', s.effective_overall,
        'improvisation_penalty', s.improvisation_penalty
      ) ORDER BY s.club_id, s.used_position, s.slot_index), '[]'::jsonb)
      FROM public.match_lineup_snapshots s
      WHERE s.match_id = _match_id
    )
  );
END;
$$;

REVOKE ALL ON FUNCTION public.get_match_public_details(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.get_match_public_details(uuid) TO authenticated;
