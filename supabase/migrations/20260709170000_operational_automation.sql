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

-- Build internal cores from the currently applied public functions so the
-- public signatures stay stable while the automation path stops depending on
-- auth.uid(). The replacements below intentionally fail if the source function
-- shape has drifted, making manual review necessary instead of silently
-- creating an unsafe core.
DO $$
DECLARE
  _sql text;
  _start integer;
  _finish integer;
BEGIN
  SELECT pg_get_functiondef('public.simulate_match(uuid)'::regprocedure) INTO _sql;

  _sql := replace(
    _sql,
    'CREATE OR REPLACE FUNCTION public.simulate_match(_match_id uuid)',
    'CREATE OR REPLACE FUNCTION public._match_simulate_internal(_match_id uuid)'
  );
  _sql := replace(_sql, E'  _admin_id uuid := public._assert_approved_admin();\n', '');
  _sql := replace(
    _sql,
    E'\n  IF NOT EXISTS (\n    SELECT 1\n    FROM public.matches pending\n    WHERE pending.round_id = _round.id\n      AND pending.status <> ''finished''::public.match_status\n  ) THEN\n    UPDATE public.rounds\n    SET is_processed = true\n    WHERE id = _round.id;\n  END IF;\n',
    E'\n'
  );

  _start := strpos(
    _sql,
    E'\n  INSERT INTO public.admin_audit_logs(admin_id, action, target_table, target_id, payload)\n  VALUES (\n    _admin_id,\n    ''simulate_match'','
  );
  _finish := strpos(_sql, E'\n\n  RETURN public._match_result_json(_match.id);');
  IF _start = 0 OR _finish = 0 OR _finish <= _start THEN
    RAISE EXCEPTION 'simulate_match_source_shape_changed';
  END IF;
  _sql := substr(_sql, 1, _start - 1) || substr(_sql, _finish + 1);

  EXECUTE _sql;
END $$;

DO $$
DECLARE
  _sql text;
  _start integer;
  _finish integer;
BEGIN
  SELECT pg_get_functiondef('public.simulate_round(uuid)'::regprocedure) INTO _sql;

  _sql := replace(
    _sql,
    'CREATE OR REPLACE FUNCTION public.simulate_round(_round_id uuid)',
    'CREATE OR REPLACE FUNCTION public._round_simulate_internal(_round_id uuid)'
  );
  _sql := replace(_sql, E'  _admin_id uuid := public._assert_approved_admin();\n', '');
  _sql := replace(
    _sql,
    'SELECT public.simulate_match(_match.id) INTO _result;',
    'SELECT public._match_simulate_internal(_match.id) INTO _result;'
  );
  _sql := replace(
    _sql,
    E'\n  IF NOT EXISTS (\n    SELECT 1\n    FROM public.matches pending\n    WHERE pending.round_id = _round.id\n      AND pending.status <> ''finished''::public.match_status\n  ) THEN\n    UPDATE public.rounds\n    SET is_processed = true\n    WHERE id = _round.id;\n  END IF;\n',
    E'\n'
  );
  _sql := replace(
    _sql,
    E'\n  FOR _match IN\n',
    E'\n  UPDATE public.rounds\n  SET simulation_started_at = coalesce(simulation_started_at, pg_catalog.now())\n  WHERE id = _round.id;\n\n  FOR _match IN\n'
  );

  _start := strpos(
    _sql,
    E'\n  INSERT INTO public.admin_audit_logs(admin_id, action, target_table, target_id, payload)\n  VALUES (\n    _admin_id,\n    ''simulate_round'','
  );
  _finish := strpos(_sql, E'\n\n  RETURN jsonb_build_object(');
  IF _start = 0 OR _finish = 0 OR _finish <= _start THEN
    RAISE EXCEPTION 'simulate_round_source_shape_changed';
  END IF;
  _sql := substr(_sql, 1, _start - 1) || substr(_sql, _finish + 1);

  EXECUTE _sql;
END $$;

DO $$
DECLARE
  _sql text;
  _start integer;
  _finish integer;
BEGIN
  SELECT pg_get_functiondef('public.season_finish(uuid)'::regprocedure) INTO _sql;

  _sql := replace(
    _sql,
    'CREATE OR REPLACE FUNCTION public.season_finish(_season_id uuid DEFAULT NULL::uuid)',
    'CREATE OR REPLACE FUNCTION public._season_finish_internal(_season_id uuid DEFAULT NULL::uuid)'
  );
  _sql := replace(
    _sql,
    'CREATE OR REPLACE FUNCTION public.season_finish(_season_id uuid DEFAULT NULL)',
    'CREATE OR REPLACE FUNCTION public._season_finish_internal(_season_id uuid DEFAULT NULL)'
  );
  _sql := replace(_sql, E'  _admin_id uuid := public._assert_approved_admin();\n', '');

  _start := strpos(
    _sql,
    E'\n  INSERT INTO public.admin_audit_logs(admin_id, action, target_table, target_id, payload)\n  VALUES (\n    _admin_id,\n    ''season_finish'','
  );
  _finish := strpos(_sql, E'\n\n  RETURN jsonb_build_object(');
  IF _start = 0 OR _finish = 0 OR _finish <= _start THEN
    RAISE EXCEPTION 'season_finish_source_shape_changed';
  END IF;
  _sql := substr(_sql, 1, _start - 1) || substr(_sql, _finish + 1);

  EXECUTE _sql;
END $$;

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
  SELECT coalesce((result->>'manual_retry_count')::integer, 0) + 1
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
      next_retry_at = NULL,
      started_at = NULL,
      finished_at = NULL,
      last_error = NULL,
      result = coalesce(result, '{}'::jsonb) || jsonb_build_object(
        'manual_retry_requested_at', pg_catalog.now(),
        'manual_retry_count', _manual_retry_count
      )
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
        result = coalesce(_result, '{}'::jsonb)
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
        result = jsonb_build_object(
          'error', SQLERRM,
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
    RAISE NOTICE 'pg_cron unavailable; use POST /api/internal/jobs/process-due-rounds as the scheduler equivalent';
  END;

  IF EXISTS (
    SELECT 1
    FROM pg_catalog.pg_namespace
    WHERE nspname = 'cron'
  ) THEN
    PERFORM cron.unschedule(jobid)
    FROM cron.job
    WHERE jobname = 'bagrefut-process-due-rounds';

    PERFORM cron.schedule(
      'bagrefut-process-due-rounds',
      '* * * * *',
      'SELECT public.process_due_rounds(now());'
    );
  END IF;
END $$;
