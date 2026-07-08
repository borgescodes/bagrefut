-- Local database contract test for participant-only match_events RLS.
-- Intended for a local Supabase/Postgres database after applying
-- 20260708120000_match_events_rls.sql. The script rolls back all fixture data.
--
-- Denied direct table/join access may return zero rows by RLS or raise a
-- permission error when base-table grants are absent. Both are accepted below.

BEGIN;

DO $$
DECLARE
  _league_id uuid;
  _badge_id uuid;
  _admin_approved uuid := '00000000-0000-0000-0000-000000021001'::uuid;
  _admin_pending uuid := '00000000-0000-0000-0000-000000021002'::uuid;
  _admin_blocked uuid := '00000000-0000-0000-0000-000000021003'::uuid;
  _home_user uuid := '00000000-0000-0000-0000-000000021004'::uuid;
  _away_user uuid := '00000000-0000-0000-0000-000000021005'::uuid;
  _stranger_user uuid := '00000000-0000-0000-0000-000000021006'::uuid;
  _pending_user uuid := '00000000-0000-0000-0000-000000021007'::uuid;
  _blocked_user uuid := '00000000-0000-0000-0000-000000021008'::uuid;
  _no_profile_user uuid := '00000000-0000-0000-0000-000000021009'::uuid;
  _home_club uuid := '00000000-0000-0000-0000-000000021101'::uuid;
  _away_club uuid := '00000000-0000-0000-0000-000000021102'::uuid;
  _stranger_club uuid := '00000000-0000-0000-0000-000000021103'::uuid;
  _season_id uuid := '00000000-0000-0000-0000-000000021201'::uuid;
  _round_id uuid := '00000000-0000-0000-0000-000000021301'::uuid;
  _match_id uuid := '00000000-0000-0000-0000-000000021401'::uuid;
  _player_id uuid := '00000000-0000-0000-0000-000000021501'::uuid;
  _event_id uuid := '00000000-0000-0000-0000-000000021601'::uuid;
  _all_users uuid[];
  _count integer;
  _message text;
  _blocked boolean;
  _has_normalized_name boolean;
BEGIN
  _all_users := ARRAY[
    _admin_approved,
    _admin_pending,
    _admin_blocked,
    _home_user,
    _away_user,
    _stranger_user,
    _pending_user,
    _blocked_user,
    _no_profile_user
  ];

  SELECT l.id INTO _league_id
  FROM public.leagues l
  WHERE l.slug = 'bagreleirao';

  IF _league_id IS NULL THEN
    RAISE EXCEPTION 'test_setup_failed: bagreleirao league not found';
  END IF;

  SELECT b.id INTO _badge_id
  FROM public.club_badges b
  WHERE b.is_active
  ORDER BY b.sort_order, b.code
  LIMIT 1;

  IF _badge_id IS NULL THEN
    RAISE EXCEPTION 'test_setup_failed: active badge not found';
  END IF;

  SELECT EXISTS (
    SELECT 1
    FROM information_schema.columns
    WHERE table_schema = 'public'
      AND table_name = 'clubs'
      AND column_name = 'normalized_name'
  )
  INTO _has_normalized_name;

  DELETE FROM public.match_events me WHERE me.id = _event_id OR me.match_id = _match_id;
  DELETE FROM public.matches m WHERE m.id = _match_id;
  DELETE FROM public.rounds r WHERE r.id = _round_id;
  DELETE FROM public.seasons s WHERE s.id = _season_id;
  DELETE FROM public.club_players cp USING public.players p WHERE cp.player_id = p.id AND p.id = _player_id;
  DELETE FROM public.players p WHERE p.id = _player_id OR p.code = 'BF-MEV-RLS-01';
  DELETE FROM public.clubs c WHERE c.id IN (_home_club, _away_club, _stranger_club) OR c.owner_id = ANY(_all_users);
  DELETE FROM public.user_roles ur WHERE ur.user_id = ANY(_all_users);
  DELETE FROM public.profiles p WHERE p.id = ANY(_all_users);
  DELETE FROM auth.users u WHERE u.id = ANY(_all_users);

  FOR _count IN 1..pg_catalog.array_length(_all_users, 1) LOOP
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
      _all_users[_count],
      '00000000-0000-0000-0000-000000000000',
      'authenticated',
      'authenticated',
      'match-events-rls-' || _count::text || '@example.test',
      'test-password',
      pg_catalog.now(),
      '{"provider":"email","providers":["email"]}'::jsonb,
      pg_catalog.jsonb_build_object('username', 'mevrls' || pg_catalog.lpad(_count::text, 2, '0')),
      pg_catalog.now(),
      pg_catalog.now()
    );
  END LOOP;

  DELETE FROM public.profiles p WHERE p.id = _no_profile_user;

  UPDATE public.profiles
  SET status = 'approved'::public.user_status
  WHERE id IN (_admin_approved, _home_user, _away_user, _stranger_user);

  UPDATE public.profiles
  SET status = 'pending'::public.user_status
  WHERE id IN (_admin_pending, _pending_user);

  UPDATE public.profiles
  SET status = 'blocked'::public.user_status
  WHERE id IN (_admin_blocked, _blocked_user);

  INSERT INTO public.user_roles (user_id, role)
  VALUES
    (_admin_approved, 'admin'::public.app_role),
    (_admin_pending, 'admin'::public.app_role),
    (_admin_blocked, 'admin'::public.app_role);

  IF _has_normalized_name THEN
    INSERT INTO public.clubs (id, league_id, owner_id, name, normalized_name, abbreviation, badge_id, balance_cents)
    VALUES
      (_home_club, _league_id, _home_user, 'MEV Home', public.normalize_club_name('MEV Home'), 'MEH', _badge_id, 0),
      (_away_club, _league_id, _away_user, 'MEV Away', public.normalize_club_name('MEV Away'), 'MEA', _badge_id, 0),
      (_stranger_club, _league_id, _stranger_user, 'MEV Other', public.normalize_club_name('MEV Other'), 'MEO', _badge_id, 0);
  ELSE
    INSERT INTO public.clubs (id, league_id, owner_id, name, abbreviation, badge_id, balance_cents)
    VALUES
      (_home_club, _league_id, _home_user, 'MEV Home', 'MEH', _badge_id, 0),
      (_away_club, _league_id, _away_user, 'MEV Away', 'MEA', _badge_id, 0),
      (_stranger_club, _league_id, _stranger_user, 'MEV Other', 'MEO', _badge_id, 0);
  END IF;

  INSERT INTO public.seasons (id, league_id, season_number, status, started_at)
  VALUES (_season_id, _league_id, 21001, 'active', pg_catalog.now());

  INSERT INTO public.rounds (id, season_id, round_number, lineup_lock_at, starts_at, ends_at)
  VALUES (_round_id, _season_id, 1, pg_catalog.now() - interval '3 days', pg_catalog.now() - interval '2 days', pg_catalog.now() - interval '1 day');

  INSERT INTO public.matches (id, round_id, home_club_id, away_club_id, home_goals, away_goals, status, simulated_at)
  VALUES (_match_id, _round_id, _home_club, _away_club, 2, 1, 'finished'::public.match_status, pg_catalog.now() - interval '1 day');

  INSERT INTO public.players (
    id, code, name, position, rarity, sector, overall, velocity, finishing,
    passing, dribbling, defending, physical, goalkeeping, reference_value_cents
  )
  VALUES (
    _player_id, 'BF-MEV-RLS-01', 'Match Event RLS Player', 'ATA'::public.player_position,
    'peba'::public.player_rarity, 'centro'::public.player_sector, 50, 50, 50,
    50, 50, 50, 50, 50, 100
  );

  INSERT INTO public.match_events (id, match_id, minute, reveal_at, event_type, club_id, player_id, meta)
  VALUES (
    _event_id,
    _match_id,
    12,
    pg_catalog.now() - interval '1 day',
    'goal'::public.match_event_type,
    _home_club,
    _player_id,
    '{"description":"private minute by minute"}'::jsonb
  );

  SELECT pg_catalog.count(*) INTO _count
  FROM pg_catalog.pg_class cls
  JOIN pg_catalog.pg_namespace nsp ON nsp.oid = cls.relnamespace
  WHERE nsp.nspname = 'public'
    AND cls.relname = 'match_events'
    AND cls.relrowsecurity
    AND cls.relforcerowsecurity;

  IF _count <> 1 THEN
    RAISE EXCEPTION 'assertion_failed: match_events RLS/FORCE RLS not enabled';
  END IF;

  SELECT pg_catalog.count(*) INTO _count
  FROM pg_catalog.pg_policies
  WHERE schemaname = 'public'
    AND tablename = 'match_events'
    AND policyname = 'match_events_approved_participant_or_admin_read'
    AND cmd = 'SELECT';

  IF _count <> 1 THEN
    RAISE EXCEPTION 'assertion_failed: expected match_events SELECT policy not found';
  END IF;

  SELECT pg_catalog.count(*) INTO _count
  FROM pg_catalog.pg_policies
  WHERE schemaname = 'public'
    AND tablename = 'match_events'
    AND policyname <> 'match_events_approved_participant_or_admin_read';

  IF _count <> 0 THEN
    RAISE EXCEPTION 'assertion_failed: conflicting match_events policies remain';
  END IF;

  BEGIN
    EXECUTE 'SET LOCAL ROLE anon';
    SELECT pg_catalog.count(*) INTO _count FROM public.match_events WHERE match_id = _match_id;
    EXECUTE 'RESET ROLE';
    IF _count <> 0 THEN
      RAISE EXCEPTION 'assertion_failed: anon read match_events';
    END IF;
  EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS _message = MESSAGE_TEXT;
    EXECUTE 'RESET ROLE';
    IF _message LIKE 'assertion_failed:%' THEN
      RAISE;
    END IF;
  END;

  FOREACH _message IN ARRAY ARRAY['no_profile','pending','blocked','stranger','admin_pending','admin_blocked'] LOOP
    PERFORM pg_catalog.set_config(
      'request.jwt.claim.sub',
      CASE _message
        WHEN 'no_profile' THEN _no_profile_user
        WHEN 'pending' THEN _pending_user
        WHEN 'blocked' THEN _blocked_user
        WHEN 'stranger' THEN _stranger_user
        WHEN 'admin_pending' THEN _admin_pending
        ELSE _admin_blocked
      END::text,
      true
    );
    EXECUTE 'SET LOCAL ROLE authenticated';
    SELECT pg_catalog.count(*) INTO _count FROM public.match_events WHERE match_id = _match_id;
    EXECUTE 'RESET ROLE';
    IF _count <> 0 THEN
      RAISE EXCEPTION 'assertion_failed: % read match_events rows', _message;
    END IF;
  END LOOP;

  FOREACH _message IN ARRAY ARRAY['home','away','admin_approved'] LOOP
    PERFORM pg_catalog.set_config(
      'request.jwt.claim.sub',
      CASE _message
        WHEN 'home' THEN _home_user
        WHEN 'away' THEN _away_user
        ELSE _admin_approved
      END::text,
      true
    );
    EXECUTE 'SET LOCAL ROLE authenticated';
    SELECT pg_catalog.count(*) INTO _count FROM public.match_events WHERE match_id = _match_id;
    EXECUTE 'RESET ROLE';
    IF _count <> 1 THEN
      RAISE EXCEPTION 'assertion_failed: % expected 1 match_event, got %', _message, _count;
    END IF;
  END LOOP;

  PERFORM pg_catalog.set_config('request.jwt.claim.sub', _stranger_user::text, true);
  EXECUTE 'SET LOCAL ROLE authenticated';
  SELECT pg_catalog.count(*) INTO _count
  FROM public.match_events
  WHERE match_id = _match_id
    AND reveal_at <= pg_catalog.now();
  EXECUTE 'RESET ROLE';
  IF _count <> 0 THEN
    RAISE EXCEPTION 'assertion_failed: stranger read revealed event';
  END IF;

  PERFORM pg_catalog.set_config('request.jwt.claim.sub', _stranger_user::text, true);
  EXECUTE 'SET LOCAL ROLE authenticated';
  SELECT pg_catalog.count(*) INTO _count
  FROM public.match_events me
  WHERE me.match_id IN (
    SELECT m.id FROM public.matches m WHERE m.status = 'finished'::public.match_status
  );
  EXECUTE 'RESET ROLE';
  IF _count <> 0 THEN
    RAISE EXCEPTION 'assertion_failed: stranger read finished match event';
  END IF;

  FOREACH _message IN ARRAY ARRAY['insert','update','delete'] LOOP
    _blocked := false;
    PERFORM pg_catalog.set_config('request.jwt.claim.sub', _home_user::text, true);
    BEGIN
      EXECUTE 'SET LOCAL ROLE authenticated';
      IF _message = 'insert' THEN
        INSERT INTO public.match_events (match_id, minute, reveal_at, event_type)
        VALUES (_match_id, 13, pg_catalog.now(), 'shot'::public.match_event_type);
      ELSIF _message = 'update' THEN
        UPDATE public.match_events SET minute = 14 WHERE id = _event_id;
      ELSE
        DELETE FROM public.match_events WHERE id = _event_id;
      END IF;
      EXECUTE 'RESET ROLE';
    EXCEPTION WHEN OTHERS THEN
      _blocked := true;
      EXECUTE 'RESET ROLE';
    END;

    IF NOT _blocked THEN
      RAISE EXCEPTION 'assertion_failed: authenticated % on match_events succeeded', _message;
    END IF;
  END LOOP;

  PERFORM pg_catalog.set_config('request.jwt.claim.sub', _stranger_user::text, true);
  EXECUTE 'SET LOCAL ROLE authenticated';
  SELECT pg_catalog.count(*) INTO _count
  FROM public.list_match_score_summaries(_match_id)
  WHERE match_id = _match_id
    AND home_goals = 2
    AND away_goals = 1
    AND final_result = 'home_win';
  EXECUTE 'RESET ROLE';
  IF _count <> 1 THEN
    RAISE EXCEPTION 'assertion_failed: approved stranger could not read score summary';
  END IF;

  PERFORM pg_catalog.set_config('request.jwt.claim.sub', _stranger_user::text, true);
  EXECUTE 'SET LOCAL ROLE authenticated';
  SELECT pg_catalog.count(*) INTO _count
  FROM public.list_match_score_summaries(_match_id) s
  WHERE pg_catalog.to_jsonb(s)::text ILIKE '%private minute by minute%'
     OR pg_catalog.to_jsonb(s)::text ILIKE '%event_type%'
     OR pg_catalog.to_jsonb(s)::text ILIKE '%player_id%'
     OR pg_catalog.to_jsonb(s)::text ILIKE '%seed%';
  EXECUTE 'RESET ROLE';
  IF _count <> 0 THEN
    RAISE EXCEPTION 'assertion_failed: score summary leaked event/internal data';
  END IF;

  FOREACH _message IN ARRAY ARRAY['pending','blocked'] LOOP
    PERFORM pg_catalog.set_config(
      'request.jwt.claim.sub',
      CASE _message WHEN 'pending' THEN _pending_user ELSE _blocked_user END::text,
      true
    );
    BEGIN
      EXECUTE 'SET LOCAL ROLE authenticated';
      PERFORM * FROM public.list_match_score_summaries(_match_id);
      EXECUTE 'RESET ROLE';
      RAISE EXCEPTION 'assertion_failed: % read score summary', _message;
    EXCEPTION WHEN OTHERS THEN
      GET STACKED DIAGNOSTICS _message = MESSAGE_TEXT;
      EXECUTE 'RESET ROLE';
      IF _message <> 'profile_not_approved' THEN
        RAISE EXCEPTION 'assertion_failed: expected profile_not_approved, got %', _message;
      END IF;
    END;
  END LOOP;

  BEGIN
    EXECUTE 'SET LOCAL ROLE anon';
    PERFORM * FROM public.list_match_score_summaries(_match_id);
    EXECUTE 'RESET ROLE';
    RAISE EXCEPTION 'assertion_failed: anon executed score summary RPC';
  EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS _message = MESSAGE_TEXT;
    EXECUTE 'RESET ROLE';
    IF _message LIKE 'assertion_failed:%' THEN
      RAISE;
    END IF;
  END;

  IF public.user_participates_in_match(_home_user, _match_id) IS NOT TRUE THEN
    RAISE EXCEPTION 'assertion_failed: helper false for home user';
  END IF;

  IF public.user_participates_in_match(_away_user, _match_id) IS NOT TRUE THEN
    RAISE EXCEPTION 'assertion_failed: helper false for away user';
  END IF;

  IF public.user_participates_in_match(_stranger_user, _match_id) IS NOT FALSE THEN
    RAISE EXCEPTION 'assertion_failed: helper true for stranger user';
  END IF;

  IF public.user_participates_in_match(
    '00000000-0000-0000-0000-000000029999'::uuid,
    '00000000-0000-0000-0000-000000029998'::uuid
  ) IS NOT FALSE THEN
    RAISE EXCEPTION 'assertion_failed: helper true for nonexistent ids';
  END IF;

  PERFORM pg_catalog.set_config('request.jwt.claim.sub', _stranger_user::text, true);
  BEGIN
    EXECUTE 'SET LOCAL ROLE authenticated';
    EXECUTE 'SELECT count(*) FROM public.matches m LEFT JOIN public.match_events me ON me.match_id = m.id WHERE m.id = $1 AND me.id IS NOT NULL'
      INTO _count
      USING _match_id;
    EXECUTE 'RESET ROLE';
    IF _count <> 0 THEN
      RAISE EXCEPTION 'assertion_failed: direct join leaked match_events';
    END IF;
  EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS _message = MESSAGE_TEXT;
    EXECUTE 'RESET ROLE';
    IF _message LIKE 'assertion_failed:%' THEN
      RAISE;
    END IF;
  END;

  PERFORM pg_catalog.set_config('request.jwt.claim.sub', _stranger_user::text, true);
  BEGIN
    EXECUTE 'SET LOCAL ROLE authenticated';
    EXECUTE 'SELECT count(*) FROM public.matches WHERE id = $1'
      INTO _count
      USING _match_id;
    EXECUTE 'RESET ROLE';
    IF _count <> 0 THEN
      RAISE EXCEPTION 'assertion_failed: direct matches table exposed base row';
    END IF;
  EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS _message = MESSAGE_TEXT;
    EXECUTE 'RESET ROLE';
    IF _message LIKE 'assertion_failed:%' THEN
      RAISE;
    END IF;
  END;

  RAISE NOTICE 'match_events_rls contract test passed';
END $$;

ROLLBACK;

-- Manual Lovable SQL Editor order:
-- 1. Run supabase/migrations/20260708120000_match_events_rls.sql.
-- 2. Run this test script in a non-production validation database when
--    impersonation with SET LOCAL ROLE/request.jwt.claim.sub is acceptable.
-- Expected result: NOTICE 'match_events_rls contract test passed', then rollback.
