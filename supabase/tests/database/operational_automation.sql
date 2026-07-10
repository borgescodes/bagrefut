-- Local database contract test for automatic operational processing.
-- Intended for a local Supabase/Postgres database after applying
-- 20260709170000_operational_automation.sql. It is transactional and rolls
-- back all fixture data.

BEGIN;

DO $$
DECLARE
  _league_id uuid;
  _badge_id uuid;
  _users uuid[] := ARRAY[
    '00000000-0000-0000-0000-000000071701'::uuid,
    '00000000-0000-0000-0000-000000071702'::uuid,
    '00000000-0000-0000-0000-000000071703'::uuid,
    '00000000-0000-0000-0000-000000071704'::uuid,
    '00000000-0000-0000-0000-000000071705'::uuid,
    '00000000-0000-0000-0000-000000071706'::uuid
  ];
  _clubs uuid[] := ARRAY[
    '00000000-0000-0000-0000-000000071801'::uuid,
    '00000000-0000-0000-0000-000000071802'::uuid,
    '00000000-0000-0000-0000-000000071803'::uuid,
    '00000000-0000-0000-0000-000000071804'::uuid,
    '00000000-0000-0000-0000-000000071805'::uuid,
    '00000000-0000-0000-0000-000000071806'::uuid
  ];
  _season_id uuid := '00000000-0000-0000-0000-000000071900'::uuid;
  _round_ids uuid[] := ARRAY[]::uuid[];
  _round_id uuid;
  _round_two uuid;
  _base timestamptz := '2026-07-09 21:55:00-03'::timestamptz;
  _result jsonb;
  _job public.operational_job_runs%ROWTYPE;
  _count integer;
  _reward_count integer;
  _prize_count integer;
  _audit_before integer;
  _audit_after integer;
  _match_id uuid;
  _player_id uuid;
  _card_id uuid;
  _definition text;
  _i integer;
  _slot integer;
BEGIN
  SELECT id INTO _league_id FROM public.leagues WHERE slug = 'bagreleirao';
  IF _league_id IS NULL THEN RAISE EXCEPTION 'test_setup_failed: league_missing'; END IF;

  SELECT id INTO _badge_id
  FROM public.club_badges
  WHERE is_active
  ORDER BY sort_order, code
  LIMIT 1;
  IF _badge_id IS NULL THEN RAISE EXCEPTION 'test_setup_failed: badge_missing'; END IF;

  IF pg_catalog.to_regclass('public.operational_job_runs') IS NULL
     OR pg_catalog.to_regprocedure('public.process_due_rounds(timestamptz)') IS NULL THEN
    RAISE EXCEPTION 'assertion_failed: operational DB layer missing without dependency on pg_cron';
  END IF;

  SELECT pg_catalog.pg_get_functiondef('public._match_simulate_internal(uuid)'::regprocedure)
  INTO _definition;
  IF _definition LIKE '%auth.uid(%'
     OR _definition LIKE '%_assert_approved_admin%'
     OR _definition LIKE '%admin_audit_logs%'
     OR _definition LIKE '%SET is_processed = true%' THEN
    RAISE EXCEPTION 'assertion_failed: match core contains auth, audit, or round-finalize logic';
  END IF;

  SELECT pg_catalog.pg_get_functiondef('public._round_simulate_internal(uuid)'::regprocedure)
  INTO _definition;
  IF _definition LIKE '%auth.uid(%'
     OR _definition LIKE '%_assert_approved_admin%'
     OR _definition LIKE '%admin_audit_logs%'
     OR _definition LIKE '%SET is_processed = true%' THEN
    RAISE EXCEPTION 'assertion_failed: round core contains auth, audit, or round-finalize logic';
  END IF;

  SELECT pg_catalog.pg_get_functiondef('public._season_finish_internal(uuid)'::regprocedure)
  INTO _definition;
  IF _definition LIKE '%auth.uid(%'
     OR _definition LIKE '%_assert_approved_admin%'
     OR _definition LIKE '%admin_audit_logs%' THEN
    RAISE EXCEPTION 'assertion_failed: season core contains auth or audit logic';
  END IF;

  CREATE TEMP TABLE pg_temp.oa_pairs(
    round_number integer NOT NULL,
    home_idx integer NOT NULL,
    away_idx integer NOT NULL
  ) ON COMMIT DROP;

  INSERT INTO pg_temp.oa_pairs(round_number, home_idx, away_idx)
  VALUES
    (1, 1, 2), (1, 3, 4), (1, 5, 6),
    (2, 1, 3), (2, 2, 5), (2, 4, 6),
    (3, 1, 4), (3, 2, 6), (3, 3, 5),
    (4, 1, 5), (4, 2, 4), (4, 3, 6),
    (5, 1, 6), (5, 2, 3), (5, 4, 5),
    (6, 2, 1), (6, 4, 3), (6, 6, 5),
    (7, 3, 1), (7, 5, 2), (7, 6, 4),
    (8, 4, 1), (8, 6, 2), (8, 5, 3),
    (9, 5, 1), (9, 4, 2), (9, 6, 3),
    (10, 6, 1), (10, 3, 2), (10, 5, 4);

  DELETE FROM public.operational_job_runs WHERE target_id = _season_id;
  DELETE FROM public.match_lineup_snapshots WHERE club_id = ANY(_clubs);
  DELETE FROM public.match_statistics WHERE club_id = ANY(_clubs);
  DELETE FROM public.wallet_transactions WHERE club_id = ANY(_clubs);
  DELETE FROM public.match_events WHERE match_id IN (
    SELECT m.id FROM public.matches m WHERE m.home_club_id = ANY(_clubs) OR m.away_club_id = ANY(_clubs)
  );
  DELETE FROM public.lineup_players lp
  USING public.lineups l
  WHERE lp.lineup_id = l.id
    AND l.club_id = ANY(_clubs);
  DELETE FROM public.lineups WHERE club_id = ANY(_clubs);
  DELETE FROM public.matches WHERE home_club_id = ANY(_clubs) OR away_club_id = ANY(_clubs);
  DELETE FROM public.rounds WHERE season_id = _season_id;
  DELETE FROM public.season_participants WHERE season_id = _season_id;
  DELETE FROM public.season_final_standings WHERE season_id = _season_id;
  DELETE FROM public.seasons WHERE id = _season_id;
  DELETE FROM public.club_player_attribute_progress cpp
  USING public.club_players cp
  WHERE cpp.club_player_id = cp.id
    AND (cp.club_id = ANY(_clubs) OR cp.player_id IN (SELECT id FROM public.players WHERE code LIKE 'BFOA-%'));
  DELETE FROM public.club_players
  WHERE club_id = ANY(_clubs)
     OR player_id IN (SELECT id FROM public.players WHERE code LIKE 'BFOA-%');
  DELETE FROM public.players WHERE code LIKE 'BFOA-%';
  DELETE FROM public.clubs WHERE id = ANY(_clubs) OR owner_id = ANY(_users);
  DELETE FROM public.user_roles WHERE user_id = ANY(_users);
  DELETE FROM public.profiles WHERE id = ANY(_users);
  DELETE FROM auth.users WHERE id = ANY(_users);

  FOR _i IN 1..6 LOOP
    INSERT INTO auth.users (
      id,
      instance_id,
      aud,
      role,
      email,
      encrypted_password,
      email_confirmed_at,
      raw_app_meta_data,
      raw_user_meta_data,
      created_at,
      updated_at
    )
    VALUES (
      _users[_i],
      '00000000-0000-0000-0000-000000000000',
      'authenticated',
      'authenticated',
      'operational-' || _i::text || '@example.test',
      'test-password',
      pg_catalog.now(),
      '{"provider":"email","providers":["email"]}'::jsonb,
      pg_catalog.jsonb_build_object('username', 'oper' || pg_catalog.lpad(_i::text, 2, '0')),
      pg_catalog.now(),
      pg_catalog.now()
    );

    INSERT INTO public.clubs (
      id,
      league_id,
      owner_id,
      name,
      normalized_name,
      abbreviation,
      badge_id,
      balance_cents,
      is_active
    )
    VALUES (
      _clubs[_i],
      _league_id,
      _users[_i],
      'Operational Club ' || _i::text,
      public.normalize_club_name('Operational Club ' || _i::text),
      'O' || pg_catalog.chr(64 + _i),
      _badge_id,
      0,
      true
    );
  END LOOP;

  UPDATE public.profiles SET status = 'approved'::public.user_status WHERE id = ANY(_users);
  INSERT INTO public.user_roles(user_id, role)
  VALUES (_users[1], 'admin'::public.app_role);

  INSERT INTO public.seasons(id, league_id, season_number, status, started_at, name)
  VALUES (_season_id, _league_id, 9701, 'active', _base, 'Operational Automation SQL');

  INSERT INTO public.season_participants(season_id, club_id, sort_order)
  SELECT _season_id, _clubs[i], i::smallint
  FROM generate_subscripts(_clubs, 1) AS selected(i);

  FOR _i IN 1..10 LOOP
    _round_id := gen_random_uuid();
    _round_ids := _round_ids || _round_id;

    INSERT INTO public.rounds(
      id,
      season_id,
      round_number,
      lineup_lock_at,
      starts_at,
      ends_at
    )
    VALUES (
      _round_id,
      _season_id,
      _i,
      _base + ((_i - 1) * interval '1 day'),
      _base + ((_i - 1) * interval '1 day') + interval '5 minutes',
      _base + ((_i - 1) * interval '1 day') + interval '15 minutes'
    );

    INSERT INTO public.matches(id, round_id, home_club_id, away_club_id, status, scheduled_at)
    SELECT
      gen_random_uuid(),
      _round_id,
      _clubs[p.home_idx],
      _clubs[p.away_idx],
      'scheduled'::public.match_status,
      _base + ((_i - 1) * interval '1 day') + interval '5 minutes'
    FROM pg_temp.oa_pairs p
    WHERE p.round_number = _i;
  END LOOP;

  _round_two := _round_ids[2];

  FOR _i IN 1..6 LOOP
    FOR _slot IN 1..5 LOOP
      INSERT INTO public.players (
        code,
        name,
        position,
        rarity,
        sector,
        overall,
        velocity,
        finishing,
        passing,
        dribbling,
        defending,
        physical,
        goalkeeping,
        reference_value_cents
      )
      VALUES (
        'BFOA-' || _i::text || '-' || _slot::text,
        'Operational Player ' || _i::text || ' ' || _slot::text,
        (ARRAY[
          'GK'::public.player_position,
          'DEF'::public.player_position,
          'MID'::public.player_position,
          'ATA'::public.player_position,
          'DEF'::public.player_position
        ])[_slot],
        'paia'::public.player_rarity,
        'centro'::public.player_sector,
        70,
        70,
        70,
        70,
        70,
        70,
        70,
        70,
        100
      )
      RETURNING id INTO _player_id;

      SELECT id INTO _card_id
      FROM public.club_players
      WHERE player_id = _player_id
      FOR UPDATE;

      DELETE FROM public.system_market_stock
      WHERE club_player_id = _card_id;

      UPDATE public.club_players
      SET club_id = _clubs[_i],
is_reserved = false
      WHERE id = _card_id;
    END LOOP;
  END LOOP;

  SELECT public.process_due_rounds(_base - interval '1 minute') INTO _result;
  IF _result <> '{"dead": 0, "failed": 0, "locked": 0, "finalized": 0, "simulated": 0, "seasons_finished": 0}'::jsonb THEN
    RAISE EXCEPTION 'assertion_failed: before lineup_lock_at should do nothing, got %', _result;
  END IF;

  SELECT public.process_due_rounds(_base + interval '1 minute') INTO _result;
  IF (_result->>'locked')::integer <> 1 THEN
    RAISE EXCEPTION 'assertion_failed: round_lock did not succeed, got %', _result;
  END IF;

  IF NOT EXISTS (
    SELECT 1
    FROM public.operational_job_runs
    WHERE job_type = 'round_lock'
      AND target_id = _round_ids[1]
      AND status = 'succeeded'
      AND attempt_count = 1
  ) THEN
    RAISE EXCEPTION 'assertion_failed: round_lock job row missing';
  END IF;

  SELECT public.process_due_rounds(_base + interval '2 minutes') INTO _result;
  IF (_result->>'locked')::integer <> 0 THEN
    RAISE EXCEPTION 'assertion_failed: repeated lock duplicated work';
  END IF;

  SELECT pg_catalog.count(*) INTO _count
  FROM public.operational_job_runs
  WHERE job_type = 'round_lock'
    AND target_id = _round_ids[1];
  IF _count <> 1 THEN
    RAISE EXCEPTION 'assertion_failed: round_lock duplicated job rows';
  END IF;

  SELECT public.process_due_rounds(_base + interval '7 minutes') INTO _result;
  IF (_result->>'simulated')::integer <> 1 THEN
    RAISE EXCEPTION 'assertion_failed: round_simulation did not succeed, got %', _result;
  END IF;

  SELECT pg_catalog.count(*) INTO _count
  FROM public.matches
  WHERE round_id = _round_ids[1]
    AND status = 'finished'::public.match_status;
  IF _count <> 3 THEN
    RAISE EXCEPTION 'assertion_failed: expected 3 finished matches after starts_at';
  END IF;

  SELECT pg_catalog.count(*) INTO _reward_count
  FROM public.wallet_transactions wt
  JOIN public.matches m ON m.id = wt.reference_id
  WHERE m.round_id = _round_ids[1]
    AND wt.kind = 'match_reward'::public.wallet_transaction_type
    AND wt.reference_table = 'matches';
  IF _reward_count <> 6 THEN
    RAISE EXCEPTION 'assertion_failed: expected one match_reward per club per match';
  END IF;

  SELECT public.process_due_rounds(_base + interval '8 minutes') INTO _result;
  SELECT pg_catalog.count(*) INTO _count
  FROM public.wallet_transactions wt
  JOIN public.matches m ON m.id = wt.reference_id
  WHERE m.round_id = _round_ids[1]
    AND wt.kind = 'match_reward'::public.wallet_transaction_type
    AND wt.reference_table = 'matches';
  IF _count <> _reward_count THEN
    RAISE EXCEPTION 'assertion_failed: repeated simulation duplicated match rewards';
  END IF;

  SELECT id INTO _match_id
  FROM public.matches
  WHERE round_id = _round_ids[1]
  ORDER BY id
  LIMIT 1;

  SELECT pg_catalog.count(*) INTO _audit_before
  FROM public.admin_audit_logs
  WHERE action = 'simulate_match'
    AND target_id = _match_id;

  PERFORM pg_catalog.set_config('request.jwt.claim.sub', _users[1]::text, true);
  PERFORM public.simulate_match(_match_id);

  SELECT pg_catalog.count(*) INTO _audit_after
  FROM public.admin_audit_logs
  WHERE action = 'simulate_match'
    AND target_id = _match_id;

  IF _audit_after <> _audit_before + 1 THEN
    RAISE EXCEPTION 'assertion_failed: public wrapper must create exactly one audit log';
  END IF;

  IF (SELECT is_processed FROM public.rounds WHERE id = _round_ids[1]) THEN
    RAISE EXCEPTION 'assertion_failed: rounds.is_processed must remain false after simulation';
  END IF;

  SELECT public.process_due_rounds(_base + interval '16 minutes') INTO _result;
  IF (_result->>'finalized')::integer <> 1 THEN
    RAISE EXCEPTION 'assertion_failed: round_finalize did not succeed, got %', _result;
  END IF;
  IF NOT (SELECT is_processed FROM public.rounds WHERE id = _round_ids[1]) THEN
    RAISE EXCEPTION 'assertion_failed: round not marked processed after ends_at';
  END IF;

  SELECT public.process_due_rounds(_base + interval '17 minutes') INTO _result;
  IF (_result->>'finalized')::integer <> 0 THEN
    RAISE EXCEPTION 'assertion_failed: repeated finalize duplicated work';
  END IF;

  SELECT public.process_due_rounds(_base + interval '17 minutes') INTO _result;
  IF (_result->>'locked')::integer <> 0
     OR (_result->>'simulated')::integer <> 0
     OR (_result->>'finalized')::integer <> 0 THEN
    RAISE EXCEPTION 'assertion_failed: logical concurrent repeat should have no effective work';
  END IF;

  UPDATE public.club_players
  SET is_reserved = true
  WHERE club_id = ANY(_clubs);

  SELECT public.process_due_rounds(_base + interval '1 day' + interval '7 minutes') INTO _result;
  IF (_result->>'failed')::integer <> 1 THEN
    RAISE EXCEPTION 'assertion_failed: insufficient roster should fail simulation, got %', _result;
  END IF;

  SELECT * INTO _job
  FROM public.operational_job_runs
  WHERE job_type = 'round_simulation'
    AND target_id = _round_two;
  IF _job.status <> 'failed' OR _job.attempt_count <> 1 THEN
    RAISE EXCEPTION 'assertion_failed: expected first failed attempt, got %, %', _job.status, _job.attempt_count;
  END IF;

  SELECT public.process_due_rounds(_job.next_retry_at + interval '1 second') INTO _result;
  SELECT * INTO _job
  FROM public.operational_job_runs
  WHERE id = _job.id;
  IF _job.status <> 'failed' OR _job.attempt_count <> 2 THEN
    RAISE EXCEPTION 'assertion_failed: retry did not increment attempt_count';
  END IF;

  WHILE _job.attempt_count < 5 LOOP
    SELECT public.process_due_rounds(_job.next_retry_at + interval '1 second') INTO _result;
    SELECT * INTO _job
    FROM public.operational_job_runs
    WHERE id = _job.id;
  END LOOP;

  IF _job.status <> 'dead' THEN
    RAISE EXCEPTION 'assertion_failed: fifth failure should mark job dead, got %', _job.status;
  END IF;

  SELECT pg_catalog.count(*) INTO _count
  FROM public.matches
  WHERE round_id = _round_two
    AND status = 'finished'::public.match_status;
  IF _count <> 0 THEN
    RAISE EXCEPTION 'assertion_failed: failed simulation left finished matches';
  END IF;

  SELECT pg_catalog.count(*) INTO _count
  FROM public.match_events e
  JOIN public.matches m ON m.id = e.match_id
  WHERE m.round_id = _round_two;
  IF _count <> 0 THEN
    RAISE EXCEPTION 'assertion_failed: failed simulation left partial events';
  END IF;

  SELECT pg_catalog.count(*) INTO _count
  FROM public.match_lineup_snapshots s
  JOIN public.matches m ON m.id = s.match_id
  WHERE m.round_id = _round_two;
  IF _count <> 0 THEN
    RAISE EXCEPTION 'assertion_failed: failed simulation left partial snapshots';
  END IF;

  SELECT pg_catalog.count(*) INTO _count
  FROM public.wallet_transactions wt
  JOIN public.matches m ON m.id = wt.reference_id
  WHERE m.round_id = _round_two
    AND wt.kind = 'match_reward'::public.wallet_transaction_type
    AND wt.reference_table = 'matches';
  IF _count <> 0 THEN
    RAISE EXCEPTION 'assertion_failed: failed simulation left partial rewards';
  END IF;

  UPDATE public.club_players
  SET is_reserved = false
  WHERE club_id = ANY(_clubs);

  SELECT public._operational_retry_job_run(_job.id) INTO _result;
  SELECT * INTO _job
  FROM public.operational_job_runs
  WHERE id = _job.id;

  IF _job.status <> 'pending'
     OR _job.next_retry_at IS NULL
     OR _job.attempt_count <> 5
     OR coalesce((_job.result->>'manual_retry_count')::integer, 0) <> 1
     OR jsonb_array_length(coalesce(_job.result->'manual_retries', '[]'::jsonb)) <> 1 THEN
    RAISE EXCEPTION 'assertion_failed: manual retry did not preserve history or schedule immediate retry';
  END IF;

  SELECT public.process_due_rounds(_base + interval '20 days') INTO _result;
  IF (_result->>'seasons_finished')::integer <> 1 THEN
    RAISE EXCEPTION 'assertion_failed: season should finish after 10 rounds and 30 matches, got %', _result;
  END IF;

  IF (SELECT pg_catalog.count(*) FROM public.rounds WHERE season_id = _season_id) <> 10 THEN
    RAISE EXCEPTION 'assertion_failed: expected 10 rounds';
  END IF;

  SELECT pg_catalog.count(*) INTO _count
  FROM public.matches m
  JOIN public.rounds r ON r.id = m.round_id
  WHERE r.season_id = _season_id
    AND m.status = 'finished'::public.match_status;
  IF _count <> 30 THEN
    RAISE EXCEPTION 'assertion_failed: expected 30 finished matches';
  END IF;

  IF (SELECT status FROM public.seasons WHERE id = _season_id) <> 'finished' THEN
    RAISE EXCEPTION 'assertion_failed: season not finished';
  END IF;

  SELECT pg_catalog.count(*) INTO _prize_count
  FROM public.wallet_transactions
  WHERE reference_table = 'seasons'
    AND reference_id = _season_id
    AND kind = 'season_prize'::public.wallet_transaction_type;
  IF _prize_count <> 6 THEN
    RAISE EXCEPTION 'assertion_failed: expected one season_prize per club';
  END IF;

  SELECT public.process_due_rounds(_base + interval '21 days') INTO _result;
  SELECT pg_catalog.count(*) INTO _count
  FROM public.wallet_transactions
  WHERE reference_table = 'seasons'
    AND reference_id = _season_id
    AND kind = 'season_prize'::public.wallet_transaction_type;
  IF _count <> _prize_count THEN
    RAISE EXCEPTION 'assertion_failed: repeated season processing duplicated season_prize';
  END IF;

  RAISE NOTICE 'operational_automation contract test passed';
END $$;

ROLLBACK;
