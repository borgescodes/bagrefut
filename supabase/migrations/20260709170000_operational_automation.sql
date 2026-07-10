-- =====================================================================
-- BAGREFUT - Operational automation for round processing
-- =====================================================================

CREATE TABLE IF NOT EXISTS public.operational_job_runs (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  job_type text NOT NULL CHECK (job_type IN (
    'round_lock',
    'round_simulation',
    'round_finalize',
    'season_finalize'
  )),
  target_id uuid NOT NULL,
  scheduled_for timestamptz NOT NULL,
  status text NOT NULL DEFAULT 'pending' CHECK (status IN (
    'pending',
    'running',
    'succeeded',
    'failed',
    'dead'
  )),
  attempt_count integer NOT NULL DEFAULT 0 CHECK (attempt_count >= 0),
  max_attempts integer NOT NULL DEFAULT 5 CHECK (max_attempts > 0),
  next_retry_at timestamptz,
  started_at timestamptz,
  finished_at timestamptz,
  last_error text,
  result jsonb,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE (job_type, target_id, scheduled_for)
);

CREATE INDEX IF NOT EXISTS idx_operational_job_runs_due
  ON public.operational_job_runs(status, next_retry_at, scheduled_for);

CREATE INDEX IF NOT EXISTS idx_operational_job_runs_created_at
  ON public.operational_job_runs(created_at DESC);

DROP TRIGGER IF EXISTS trg_operational_job_runs_updated_at ON public.operational_job_runs;
CREATE TRIGGER trg_operational_job_runs_updated_at
  BEFORE UPDATE ON public.operational_job_runs
  FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();

REVOKE ALL ON public.operational_job_runs FROM PUBLIC, anon, authenticated;
GRANT ALL ON public.operational_job_runs TO service_role, postgres;

ALTER TABLE public.operational_job_runs ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "operational_job_runs_service_role_all" ON public.operational_job_runs;
CREATE POLICY "operational_job_runs_service_role_all"
ON public.operational_job_runs
FOR ALL TO service_role
USING (true)
WITH CHECK (true);

ALTER TABLE public.rounds
  ADD COLUMN IF NOT EXISTS lineups_locked_at timestamptz,
  ADD COLUMN IF NOT EXISTS simulation_started_at timestamptz,
  ADD COLUMN IF NOT EXISTS finalized_at timestamptz;

-- ---------- EXPLICIT INTERNAL CORES ----------
-- Definitions are copied explicitly from the versioned season/match engines.
-- No runtime introspection or generated function source is used.
CREATE OR REPLACE FUNCTION public._match_simulate_internal(_match_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
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



  RETURN public._match_result_json(_match.id);
END;
$$;

CREATE OR REPLACE FUNCTION public._round_simulate_internal(_round_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
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

  UPDATE public.rounds
  SET simulation_started_at = coalesce(simulation_started_at, pg_catalog.now())
  WHERE id = _round.id;

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
      SELECT public._match_simulate_internal(_match.id) INTO _result;
      _simulated_count := _simulated_count + 1;
      _results := _results || jsonb_build_array(_result);
    END IF;
  END LOOP;



  RETURN jsonb_build_object(
    'round_id', _round.id,
    'simulated_count', _simulated_count,
    'skipped_count', _skipped_count,
    'matches', _results
  );
END;
$$;

CREATE OR REPLACE FUNCTION public._season_finish_internal(_season_id uuid DEFAULT NULL)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  _season public.seasons%ROWTYPE;
  _match_total integer;
  _pending_total integer;
  _standing record;
  _champion record;
  _prize integer;
  _balance integer;
BEGIN
  SELECT * INTO _season
  FROM public.seasons
  WHERE id = COALESCE(
      _season_id,
      (SELECT active.id FROM public.seasons active WHERE active.status = 'active' ORDER BY active.started_at DESC NULLS LAST LIMIT 1)
    )
  FOR UPDATE;

  IF _season.id IS NULL THEN
    RAISE EXCEPTION 'season_not_active';
  END IF;

  IF _season.status = 'finished' THEN
    RETURN jsonb_build_object(
      'season_id', _season.id,
      'champion_club_id', _season.champion_club_id,
      'champion_points', _season.champion_points,
      'champion_wins', _season.champion_wins,
      'champion_goal_difference', _season.champion_goal_difference,
      'idempotent', true
    );
  END IF;

  IF _season.status <> 'active' THEN
    RAISE EXCEPTION 'season_not_active';
  END IF;

  SELECT
    count(*),
    count(*) FILTER (WHERE m.status <> 'finished'::public.match_status)
  INTO _match_total, _pending_total
  FROM public.matches m
  JOIN public.rounds r ON r.id = m.round_id
  WHERE r.season_id = _season.id;

  IF _match_total <> 30 OR _pending_total <> 0 THEN
    RAISE EXCEPTION 'season_has_pending_matches';
  END IF;

  INSERT INTO public.season_final_standings (
    season_id,
    club_id,
    position,
    played,
    points,
    wins,
    draws,
    losses,
    goals_for,
    goals_against,
    goal_difference,
    prize_cents
  )
  SELECT
    _season.id,
    s.club_id,
    s.position,
    s.played,
    s.points,
    s.wins,
    s.draws,
    s.losses,
    s.goals_for,
    s.goals_against,
    s.goal_difference,
    coalesce(pc.amount_cents, 0)
  FROM public.get_season_standings(_season.id) s
  LEFT JOIN public.season_prize_config pc
    ON pc.config_id = _season.config_id
   AND pc.position = s.position
  ON CONFLICT (season_id, club_id) DO NOTHING;

  SELECT * INTO _champion
  FROM public.season_final_standings
  WHERE season_id = _season.id
    AND position = 1;

  IF _champion.club_id IS NULL THEN
    RAISE EXCEPTION 'season_standings_unavailable';
  END IF;

  FOR _standing IN
    SELECT *
    FROM public.season_final_standings
    WHERE season_id = _season.id
    ORDER BY position
  LOOP
    IF EXISTS (
      SELECT 1
      FROM public.wallet_transactions wt
      WHERE wt.club_id = _standing.club_id
        AND wt.kind = 'season_prize'::public.wallet_transaction_type
        AND wt.reference_table = 'seasons'
        AND wt.reference_id = _season.id
    ) THEN
      RAISE EXCEPTION 'season_prize_already_credited';
    END IF;

    _prize := _standing.prize_cents;
    IF _prize > 0 THEN
      PERFORM public._credit_wallet(
        _standing.club_id,
        _prize,
        'season_prize'::public.wallet_transaction_type,
        'seasons',
        _season.id,
        'premiacao final posicao ' || _standing.position::text
      );
    ELSE
      SELECT balance_cents INTO _balance
      FROM public.clubs
      WHERE id = _standing.club_id;

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
        _standing.club_id,
        0,
        _balance,
        'season_prize'::public.wallet_transaction_type,
        'seasons',
        _season.id,
        'premiacao final posicao ' || _standing.position::text
      );
    END IF;
  END LOOP;

  UPDATE public.seasons
  SET status = 'finished',
      finished_at = now(),
      champion_club_id = _champion.club_id,
      champion_points = _champion.points,
      champion_wins = _champion.wins,
      champion_goal_difference = _champion.goal_difference
  WHERE id = _season.id;

  UPDATE public.leagues
  SET status = 'finished'::public.league_status
  WHERE id = _season.league_id;


  RETURN jsonb_build_object(
    'season_id', _season.id,
    'champion_club_id', _champion.club_id,
    'champion_points', _champion.points,
    'champion_wins', _champion.wins,
    'champion_goal_difference', _champion.goal_difference
  );
END;
$$;

REVOKE ALL ON FUNCTION public._match_simulate_internal(uuid) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public._round_simulate_internal(uuid) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public._season_finish_internal(uuid) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public._match_simulate_internal(uuid) TO service_role, postgres;
GRANT EXECUTE ON FUNCTION public._round_simulate_internal(uuid) TO service_role, postgres;
GRANT EXECUTE ON FUNCTION public._season_finish_internal(uuid) TO service_role, postgres;

CREATE OR REPLACE FUNCTION public._round_finalize_internal(_round_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  _round public.rounds%ROWTYPE;
  _season public.seasons%ROWTYPE;
  _match_total integer;
  _finished_total integer;
BEGIN
  SELECT * INTO _round
  FROM public.rounds
  WHERE id = _round_id
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

  IF _round.is_processed THEN
    RETURN jsonb_build_object(
      'round_id', _round.id,
      'season_id', _round.season_id,
      'finalized_at', _round.finalized_at,
      'idempotent', true
    );
  END IF;

  IF _season.status <> 'active' THEN
    RAISE EXCEPTION 'season_not_active';
  END IF;

  SELECT
    count(*),
    count(*) FILTER (WHERE status = 'finished'::public.match_status)
  INTO _match_total, _finished_total
  FROM public.matches
  WHERE round_id = _round.id;

  IF _match_total <> 3 OR _finished_total <> 3 THEN
    RAISE EXCEPTION 'round_matches_not_finished';
  END IF;

  UPDATE public.rounds
  SET is_processed = true,
      finalized_at = coalesce(finalized_at, pg_catalog.now())
  WHERE id = _round.id
  RETURNING * INTO _round;

  RETURN jsonb_build_object(
    'round_id', _round.id,
    'season_id', _round.season_id,
    'finalized_at', _round.finalized_at,
    'idempotent', false
  );
END;
$$;

REVOKE ALL ON FUNCTION public._round_finalize_internal(uuid) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public._round_finalize_internal(uuid) TO service_role, postgres;

CREATE OR REPLACE FUNCTION public.simulate_match(_match_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  _admin_id uuid := public._assert_approved_admin();
  _round_id uuid;
  _season_id uuid;
  _result jsonb;
BEGIN
  SELECT m.round_id, r.season_id
  INTO _round_id, _season_id
  FROM public.matches m
  JOIN public.rounds r ON r.id = m.round_id
  WHERE m.id = _match_id;

  SELECT public._match_simulate_internal(_match_id) INTO _result;

  INSERT INTO public.admin_audit_logs(admin_id, action, target_table, target_id, payload)
  VALUES (
    _admin_id,
    'simulate_match',
    'matches',
    _match_id,
    jsonb_build_object(
      'round_id', _round_id,
      'season_id', _season_id,
      'result', _result
    )
  );

  RETURN _result;
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
  _season_id uuid;
  _result jsonb;
BEGIN
  SELECT season_id INTO _season_id
  FROM public.rounds
  WHERE id = _round_id;

  SELECT public._round_simulate_internal(_round_id) INTO _result;

  INSERT INTO public.admin_audit_logs(admin_id, action, target_table, target_id, payload)
  VALUES (
    _admin_id,
    'simulate_round',
    'rounds',
    _round_id,
    coalesce(_result, '{}'::jsonb) || jsonb_build_object('season_id', _season_id)
  );

  RETURN _result;
END;
$$;

REVOKE ALL ON FUNCTION public.simulate_round(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.simulate_round(uuid) TO authenticated;

CREATE OR REPLACE FUNCTION public.season_finish(_season_id uuid DEFAULT NULL)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  _admin_id uuid := public._assert_approved_admin();
  _result jsonb;
  _target_id uuid;
BEGIN
  SELECT public._season_finish_internal(_season_id) INTO _result;
  _target_id := (_result->>'season_id')::uuid;

  INSERT INTO public.admin_audit_logs(admin_id, action, target_table, target_id, payload)
  VALUES (
    _admin_id,
    'season_finish',
    'seasons',
    _target_id,
    _result
  );

  RETURN _result;
END;
$$;

REVOKE ALL ON FUNCTION public.season_finish(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.season_finish(uuid) TO authenticated;

CREATE OR REPLACE FUNCTION public.admin_list_operational_job_runs(
  _limit integer DEFAULT 50,
  _status text DEFAULT NULL
)
RETURNS TABLE (
  id uuid,
  job_type text,
  target_id uuid,
  scheduled_for timestamptz,
  status text,
  attempt_count integer,
  max_attempts integer,
  next_retry_at timestamptz,
  started_at timestamptz,
  finished_at timestamptz,
  last_error text,
  result jsonb,
  created_at timestamptz,
  updated_at timestamptz
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  _safe_limit integer := least(greatest(coalesce(_limit, 50), 1), 200);
BEGIN
  PERFORM public._assert_approved_admin();

  IF _status IS NOT NULL AND _status NOT IN ('pending', 'running', 'succeeded', 'failed', 'dead') THEN
    RAISE EXCEPTION 'operational_job_status_invalid';
  END IF;

  RETURN QUERY
  SELECT
    runs.id,
    runs.job_type,
    runs.target_id,
    runs.scheduled_for,
    runs.status,
    runs.attempt_count,
    runs.max_attempts,
    runs.next_retry_at,
    runs.started_at,
    runs.finished_at,
    runs.last_error,
    runs.result,
    runs.created_at,
    runs.updated_at
  FROM public.operational_job_runs runs
  WHERE _status IS NULL OR runs.status = _status
  ORDER BY runs.created_at DESC
  LIMIT _safe_limit;
END;
$$;

REVOKE ALL ON FUNCTION public.admin_list_operational_job_runs(integer, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.admin_list_operational_job_runs(integer, text) TO authenticated;

CREATE OR REPLACE FUNCTION public._operational_retry_delay(_attempt_count integer)
RETURNS interval
LANGUAGE sql
IMMUTABLE
SECURITY DEFINER
SET search_path = ''
AS $$
  SELECT CASE least(greatest(_attempt_count, 1), 5)
    WHEN 1 THEN interval '1 minute'
    WHEN 2 THEN interval '2 minutes'
    WHEN 3 THEN interval '4 minutes'
    WHEN 4 THEN interval '8 minutes'
    ELSE interval '16 minutes'
  END
$$;

REVOKE ALL ON FUNCTION public._operational_retry_delay(integer) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public._operational_retry_delay(integer) TO service_role, postgres;

CREATE OR REPLACE FUNCTION public._operational_retry_job_run(_job_run_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  _run public.operational_job_runs%ROWTYPE;
  _manual_retry_count integer;
BEGIN
  SELECT coalesce(
    jsonb_array_length(
      CASE
        WHEN jsonb_typeof(result->'manual_retries') = 'array' THEN result->'manual_retries'
        ELSE '[]'::jsonb
      END
    ),
    0
  ) + 1
  INTO _manual_retry_count
  FROM public.operational_job_runs
  WHERE id = _job_run_id
    AND status IN ('failed', 'dead')
  FOR UPDATE;

  IF _manual_retry_count IS NULL THEN
    RAISE EXCEPTION 'job_run_not_retryable';
  END IF;

  UPDATE public.operational_job_runs
  SET status = 'pending',
      next_retry_at = pg_catalog.now(),
      started_at = NULL,
      finished_at = NULL,
      result = jsonb_set(
        coalesce(result, '{}'::jsonb),
        '{manual_retries}',
        (
CASE
  WHEN jsonb_typeof(result->'manual_retries') = 'array' THEN result->'manual_retries'
  ELSE '[]'::jsonb
END
        ) || jsonb_build_array(
jsonb_build_object(
  'requested_at', pg_catalog.now(),
  'attempt_count', attempt_count,
  'previous_status', status,
  'previous_error', last_error
)
        ),
        true
      ) || jsonb_build_object('manual_retry_count', _manual_retry_count)
  WHERE id = _job_run_id
    AND status IN ('failed', 'dead')
  RETURNING * INTO _run;

  RETURN jsonb_build_object(
    'id', _run.id,
    'job_type', _run.job_type,
    'target_id', _run.target_id,
    'scheduled_for', _run.scheduled_for,
    'status', _run.status,
    'attempt_count', _run.attempt_count,
    'manual_retry_count', _manual_retry_count
  );
END;
$$;

REVOKE ALL ON FUNCTION public._operational_retry_job_run(uuid) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public._operational_retry_job_run(uuid) TO service_role, postgres;

CREATE OR REPLACE FUNCTION public._operational_process_job(
  _job_type text,
  _target_id uuid,
  _scheduled_for timestamptz,
  _now timestamptz
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  _job public.operational_job_runs%ROWTYPE;
  _attempt integer;
  _result jsonb := '{}'::jsonb;
  _next_status text;
  _current_status text;
BEGIN
  IF _job_type NOT IN ('round_lock', 'round_simulation', 'round_finalize', 'season_finalize') THEN
    RAISE EXCEPTION 'operational_job_type_invalid';
  END IF;

  INSERT INTO public.operational_job_runs(job_type, target_id, scheduled_for, status)
  VALUES (_job_type, _target_id, _scheduled_for, 'pending')
  ON CONFLICT (job_type, target_id, scheduled_for) DO NOTHING;

  SELECT *
  INTO _job
  FROM public.operational_job_runs runs
  WHERE runs.job_type = _job_type
    AND runs.target_id = _target_id
    AND runs.scheduled_for = _scheduled_for
    AND (
      runs.status = 'pending'
      OR (
        runs.status = 'failed'
        AND (runs.next_retry_at IS NULL OR runs.next_retry_at <= _now)
      )
    )
  FOR UPDATE SKIP LOCKED;

  IF _job.id IS NULL THEN
    SELECT status INTO _current_status
    FROM public.operational_job_runs
    WHERE job_type = _job_type
      AND target_id = _target_id
      AND scheduled_for = _scheduled_for;

    RETURN jsonb_build_object(
      'status', 'skipped',
      'current_status', coalesce(_current_status, 'missing')
    );
  END IF;

  PERFORM pg_advisory_xact_lock(
    hashtext(_job.job_type),
    hashtext(_job.target_id::text || ':' || _job.scheduled_for::text)
  );

  _attempt := _job.attempt_count + 1;

  UPDATE public.operational_job_runs
  SET status = 'running',
      attempt_count = _attempt,
      started_at = pg_catalog.now(),
      finished_at = NULL,
      next_retry_at = NULL,
      last_error = NULL
  WHERE id = _job.id;

  BEGIN
    IF _job.job_type = 'round_lock' THEN
      UPDATE public.rounds
      SET lineups_locked_at = coalesce(lineups_locked_at, pg_catalog.now())
      WHERE id = _job.target_id
      RETURNING jsonb_build_object(
        'round_id', id,
        'lineups_locked_at', lineups_locked_at
      )
      INTO _result;

      IF _result IS NULL THEN
        RAISE EXCEPTION 'round_not_found';
      END IF;
    ELSIF _job.job_type = 'round_simulation' THEN
      SELECT public._round_simulate_internal(_job.target_id) INTO _result;
    ELSIF _job.job_type = 'round_finalize' THEN
      SELECT public._round_finalize_internal(_job.target_id) INTO _result;
    ELSIF _job.job_type = 'season_finalize' THEN
      SELECT public._season_finish_internal(_job.target_id) INTO _result;
    END IF;

    UPDATE public.operational_job_runs
    SET status = 'succeeded',
        finished_at = pg_catalog.now(),
        last_error = NULL,
        result = coalesce(result, '{}'::jsonb) || jsonb_build_object(
          'last_success', coalesce(_result, '{}'::jsonb),
          'attempt_count', _attempt,
          'succeeded_at', pg_catalog.now()
        )
    WHERE id = _job.id;

    RETURN jsonb_build_object(
      'status', 'succeeded',
      'job_run_id', _job.id,
      'result', coalesce(_result, '{}'::jsonb)
    );
  EXCEPTION WHEN OTHERS THEN
    _next_status := CASE WHEN _attempt >= _job.max_attempts THEN 'dead' ELSE 'failed' END;

    UPDATE public.operational_job_runs
    SET status = _next_status,
        finished_at = pg_catalog.now(),
        next_retry_at = CASE
          WHEN _next_status = 'dead' THEN NULL
          ELSE _now + public._operational_retry_delay(_attempt)
        END,
        last_error = SQLERRM,
        result = coalesce(result, '{}'::jsonb) || jsonb_build_object(
          'last_failure', jsonb_build_object(
            'error', SQLERRM,
            'attempt_count', _attempt,
            'failed_at', pg_catalog.now()
          ),
          'attempt_count', _attempt
        )
    WHERE id = _job.id;

    RETURN jsonb_build_object(
      'status', _next_status,
      'job_run_id', _job.id,
      'error', SQLERRM
    );
  END;
END;
$$;

REVOKE ALL ON FUNCTION public._operational_process_job(text, uuid, timestamptz, timestamptz) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public._operational_process_job(text, uuid, timestamptz, timestamptz) TO service_role, postgres;

CREATE OR REPLACE FUNCTION public.process_due_rounds(_now timestamptz DEFAULT now())
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  _round record;
  _season record;
  _step jsonb;
  _status text;
  _locked integer := 0;
  _simulated integer := 0;
  _finalized integer := 0;
  _seasons_finished integer := 0;
  _failed integer := 0;
  _dead integer := 0;
BEGIN
  FOR _round IN
    SELECT r.*
    FROM public.rounds r
    JOIN public.seasons s ON s.id = r.season_id
    WHERE s.status = 'active'
      AND (
        (_now >= r.lineup_lock_at AND r.lineups_locked_at IS NULL)
        OR (_now >= r.starts_at AND r.simulation_started_at IS NULL)
        OR (_now >= r.ends_at AND NOT r.is_processed)
      )
    ORDER BY r.starts_at, r.round_number
    FOR UPDATE OF r SKIP LOCKED
  LOOP
    IF _now >= _round.lineup_lock_at AND _round.lineups_locked_at IS NULL THEN
      SELECT public._operational_process_job('round_lock', _round.id, _round.lineup_lock_at, _now) INTO _step;
      _status := _step->>'status';
      IF _status = 'succeeded' THEN
        _locked := _locked + 1;
      ELSIF _status = 'failed' THEN
        _failed := _failed + 1;
      ELSIF _status = 'dead' THEN
        _dead := _dead + 1;
      END IF;
    END IF;

    IF _now >= _round.starts_at AND _round.simulation_started_at IS NULL THEN
      SELECT public._operational_process_job('round_simulation', _round.id, _round.starts_at, _now) INTO _step;
      _status := _step->>'status';
      IF _status = 'succeeded' THEN
        _simulated := _simulated + 1;
      ELSIF _status = 'failed' THEN
        _failed := _failed + 1;
      ELSIF _status = 'dead' THEN
        _dead := _dead + 1;
      END IF;
    END IF;

    IF _now >= _round.ends_at AND NOT _round.is_processed THEN
      SELECT public._operational_process_job('round_finalize', _round.id, _round.ends_at, _now) INTO _step;
      _status := _step->>'status';
      IF _status = 'succeeded' THEN
        _finalized := _finalized + 1;
      ELSIF _status = 'failed' THEN
        _failed := _failed + 1;
      ELSIF _status = 'dead' THEN
        _dead := _dead + 1;
      END IF;
    END IF;
  END LOOP;

  FOR _season IN
    SELECT
      s.id,
      max(r.ends_at) AS scheduled_for
    FROM public.seasons s
    JOIN public.rounds r ON r.season_id = s.id
    JOIN public.matches m ON m.round_id = r.id
    WHERE s.status = 'active'
    GROUP BY s.id
    HAVING count(DISTINCT r.id) = 10
       AND count(DISTINCT r.id) FILTER (WHERE r.is_processed) = 10
       AND count(m.id) = 30
       AND count(m.id) FILTER (WHERE m.status = 'finished'::public.match_status) = 30
  LOOP
    SELECT public._operational_process_job(
      'season_finalize',
      _season.id,
      _season.scheduled_for,
      _now
    ) INTO _step;
    _status := _step->>'status';
    IF _status = 'succeeded' THEN
      _seasons_finished := _seasons_finished + 1;
    ELSIF _status = 'failed' THEN
      _failed := _failed + 1;
    ELSIF _status = 'dead' THEN
      _dead := _dead + 1;
    END IF;
  END LOOP;

  RETURN jsonb_build_object(
    'locked', _locked,
    'simulated', _simulated,
    'finalized', _finalized,
    'seasons_finished', _seasons_finished,
    'failed', _failed,
    'dead', _dead
  );
END;
$$;

REVOKE ALL ON FUNCTION public.process_due_rounds(timestamptz) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.process_due_rounds(timestamptz) TO service_role, postgres;

DO $$
BEGIN
  BEGIN
    CREATE EXTENSION IF NOT EXISTS pg_cron;
  EXCEPTION WHEN OTHERS THEN
    RAISE NOTICE 'pg_cron unavailable (%); use POST /api/internal/jobs/process-due-rounds', SQLERRM;
  END;

  BEGIN
    IF pg_catalog.to_regclass('cron.job') IS NULL THEN
      RAISE NOTICE 'cron.job unavailable; operational DB functions remain active';
      RETURN;
    END IF;

    PERFORM cron.unschedule(jobid)
    FROM cron.job
    WHERE jobname = 'bagrefut-process-due-rounds';

    PERFORM cron.schedule(
      'bagrefut-process-due-rounds',
      '* * * * *',
      'SELECT public.process_due_rounds(now());'
    );
  EXCEPTION WHEN OTHERS THEN
    RAISE NOTICE 'pg_cron configuration skipped (%); operational DB functions remain active', SQLERRM;
  END;
END $$;
