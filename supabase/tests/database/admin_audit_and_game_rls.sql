-- Local database contract test for admin status audit atomicity and game RLS.
-- Intended for a local Supabase/Postgres database after applying
-- fix_admin_audit_and_game_rls. The script rolls back all fixture data.

BEGIN;

DO $$
DECLARE
  _league_id uuid;
  _badge_id uuid;
  _admin_approved uuid := '00000000-0000-0000-0000-000000011001'::uuid;
  _admin_pending uuid := '00000000-0000-0000-0000-000000011002'::uuid;
  _admin_blocked uuid := '00000000-0000-0000-0000-000000011003'::uuid;
  _user_pending uuid := '00000000-0000-0000-0000-000000011004'::uuid;
  _user_blocked uuid := '00000000-0000-0000-0000-000000011005'::uuid;
  _user_approved uuid := '00000000-0000-0000-0000-000000011006'::uuid;
  _target_user uuid := '00000000-0000-0000-0000-000000011007'::uuid;
  _club_a uuid := '00000000-0000-0000-0000-000000011101'::uuid;
  _club_b uuid := '00000000-0000-0000-0000-000000011102'::uuid;
  _season_id uuid := '00000000-0000-0000-0000-000000011201'::uuid;
  _round_id uuid := '00000000-0000-0000-0000-000000011301'::uuid;
  _match_id uuid := '00000000-0000-0000-0000-000000011401'::uuid;
  _player_id uuid := '00000000-0000-0000-0000-000000011501'::uuid;
  _extra_users uuid[] := ARRAY[
    '00000000-0000-0000-0000-000000011021'::uuid,
    '00000000-0000-0000-0000-000000011022'::uuid,
    '00000000-0000-0000-0000-000000011023'::uuid,
    '00000000-0000-0000-0000-000000011024'::uuid,
    '00000000-0000-0000-0000-000000011025'::uuid,
    '00000000-0000-0000-0000-000000011026'::uuid,
    '00000000-0000-0000-0000-000000011027'::uuid
  ];
  _all_users uuid[];
  _count integer;
  _before_count integer;
  _audit_id uuid;
  _previous_status public.user_status;
  _new_status public.user_status;
  _changed_at timestamptz;
  _payload jsonb;
  _message text;
  _i integer;
  _blocked boolean;
BEGIN
  _all_users := ARRAY[
    _admin_approved,
    _admin_pending,
    _admin_blocked,
    _user_pending,
    _user_blocked,
    _user_approved,
    _target_user
  ] || _extra_users;

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

  DELETE FROM public.admin_audit_logs aal
  WHERE aal.admin_id = ANY(_all_users)
     OR aal.target_id = ANY(_all_users);

  DELETE FROM public.matches m
  WHERE m.id = _match_id;

  DELETE FROM public.rounds r
  WHERE r.id = _round_id;

  DELETE FROM public.seasons s
  WHERE s.id = _season_id;

  DELETE FROM public.players p
  WHERE p.id = _player_id
     OR p.code = 'BFAUDIT-RLS-01';

  DELETE FROM public.clubs c
  WHERE c.id IN (_club_a, _club_b)
     OR c.owner_id = ANY(_all_users);

  DELETE FROM public.user_roles ur
  WHERE ur.user_id = ANY(_all_users);

  DELETE FROM public.profiles p
  WHERE p.id = ANY(_all_users);

  DELETE FROM auth.users u
  WHERE u.id = ANY(_all_users);

  FOR _i IN 1..pg_catalog.array_length(_all_users, 1) LOOP
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
      _all_users[_i],
      '00000000-0000-0000-0000-000000000000',
      'authenticated',
      'authenticated',
      'audit-rls-' || _i::text || '@example.test',
      'test-password',
      pg_catalog.now(),
      '{"provider":"email","providers":["email"]}'::jsonb,
      pg_catalog.jsonb_build_object('username', 'audrls' || pg_catalog.lpad(_i::text, 2, '0')),
      pg_catalog.now(),
      pg_catalog.now()
    );
  END LOOP;

  UPDATE public.profiles
  SET status = 'approved'::public.user_status
  WHERE id IN (_admin_approved, _user_approved);

  UPDATE public.profiles
  SET status = 'pending'::public.user_status
  WHERE id IN (_admin_pending, _user_pending, _target_user)
     OR id = ANY(_extra_users);

  UPDATE public.profiles
  SET status = 'blocked'::public.user_status
  WHERE id IN (_admin_blocked, _user_blocked);

  INSERT INTO public.user_roles (user_id, role)
  VALUES
    (_admin_approved, 'admin'::public.app_role),
    (_admin_pending, 'admin'::public.app_role),
    (_admin_blocked, 'admin'::public.app_role);

  INSERT INTO public.clubs (id, league_id, owner_id, name, abbreviation, badge_id, balance_cents)
  VALUES
    (_club_a, _league_id, _user_approved, 'Audit RLS A', 'ARA', _badge_id, 0),
    (_club_b, _league_id, _target_user, 'Audit RLS B', 'ARB', _badge_id, 0);

  INSERT INTO public.seasons (id, league_id, season_number, status, started_at)
  VALUES (_season_id, _league_id, 11001, 'active', pg_catalog.now());

  INSERT INTO public.rounds (id, season_id, round_number, lineup_lock_at, starts_at, ends_at)
  VALUES (_round_id, _season_id, 1, pg_catalog.now() + interval '1 day', pg_catalog.now() + interval '2 days', pg_catalog.now() + interval '3 days');

  INSERT INTO public.matches (id, round_id, home_club_id, away_club_id, status)
  VALUES (_match_id, _round_id, _club_a, _club_b, 'scheduled'::public.match_status);

  INSERT INTO public.players (
    id,
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
    _player_id,
    'BFAUDIT-RLS-01',
    'Audit RLS Player',
    'ATA'::public.player_position,
    'peba'::public.player_rarity,
    'centro'::public.player_sector,
    50,
    50,
    50,
    50,
    50,
    50,
    50,
    50,
    100
  );

  -- 1-3: users can read their own profile even when pending/blocked.
  FOREACH _payload IN ARRAY ARRAY[
    pg_catalog.jsonb_build_object('user_id', _user_pending, 'expected', 1),
    pg_catalog.jsonb_build_object('user_id', _user_blocked, 'expected', 1),
    pg_catalog.jsonb_build_object('user_id', _user_approved, 'expected', 1)
  ] LOOP
    PERFORM pg_catalog.set_config('request.jwt.claim.sub', (_payload->>'user_id')::uuid::text, true);
    EXECUTE 'SET LOCAL ROLE authenticated';
    EXECUTE 'SELECT count(*) FROM public.profiles WHERE id = $1' INTO _count USING (_payload->>'user_id')::uuid;
    EXECUTE 'RESET ROLE';

    IF _count <> (_payload->>'expected')::integer THEN
      RAISE EXCEPTION 'assertion_failed: own profile read expected %, got %', _payload->>'expected', _count;
    END IF;
  END LOOP;

  -- 4-11: pending/blocked cannot read game tables.
  FOREACH _payload IN ARRAY ARRAY[
    pg_catalog.jsonb_build_object('user_id', _user_pending, 'table_name', 'leagues'),
    pg_catalog.jsonb_build_object('user_id', _user_pending, 'table_name', 'players'),
    pg_catalog.jsonb_build_object('user_id', _user_pending, 'table_name', 'clubs'),
    pg_catalog.jsonb_build_object('user_id', _user_pending, 'table_name', 'matches'),
    pg_catalog.jsonb_build_object('user_id', _user_blocked, 'table_name', 'leagues'),
    pg_catalog.jsonb_build_object('user_id', _user_blocked, 'table_name', 'players'),
    pg_catalog.jsonb_build_object('user_id', _user_blocked, 'table_name', 'clubs'),
    pg_catalog.jsonb_build_object('user_id', _user_blocked, 'table_name', 'matches')
  ] LOOP
    PERFORM pg_catalog.set_config('request.jwt.claim.sub', (_payload->>'user_id')::uuid::text, true);
    EXECUTE 'SET LOCAL ROLE authenticated';
    EXECUTE 'SELECT count(*) FROM public.' || pg_catalog.quote_ident(_payload->>'table_name') INTO _count;
    EXECUTE 'RESET ROLE';

    IF _count <> 0 THEN
      RAISE EXCEPTION 'assertion_failed: % read % rows from %', _payload->>'user_id', _count, _payload->>'table_name';
    END IF;
  END LOOP;

  -- 12: approved users keep expected public game reads.
  PERFORM pg_catalog.set_config('request.jwt.claim.sub', _user_approved::text, true);
  EXECUTE 'SET LOCAL ROLE authenticated';
  EXECUTE 'SELECT count(*) FROM public.leagues' INTO _count;
  EXECUTE 'RESET ROLE';

  IF _count < 1 THEN
    RAISE EXCEPTION 'assertion_failed: approved user cannot read leagues';
  END IF;

  -- 13: approved admin keeps admin profile access.
  PERFORM pg_catalog.set_config('request.jwt.claim.sub', _admin_approved::text, true);
  EXECUTE 'SET LOCAL ROLE authenticated';
  EXECUTE 'SELECT count(*) FROM public.profiles WHERE id = $1' INTO _count USING _user_pending;
  EXECUTE 'RESET ROLE';

  IF _count <> 1 THEN
    RAISE EXCEPTION 'assertion_failed: approved admin cannot read another profile';
  END IF;

  -- 14: blocked admin loses admin access.
  PERFORM pg_catalog.set_config('request.jwt.claim.sub', _admin_blocked::text, true);
  EXECUTE 'SET LOCAL ROLE authenticated';
  EXECUTE 'SELECT count(*) FROM public.profiles WHERE id = $1' INTO _count USING _user_pending;
  EXECUTE 'RESET ROLE';

  IF _count <> 0 THEN
    RAISE EXCEPTION 'assertion_failed: blocked admin read another profile';
  END IF;

  -- 15-17: non-admin, pending admin and blocked admin cannot call status RPC.
  FOREACH _payload IN ARRAY ARRAY[
    pg_catalog.jsonb_build_object('user_id', _user_approved, 'expected', 'forbidden_not_admin'),
    pg_catalog.jsonb_build_object('user_id', _admin_pending, 'expected', 'profile_not_approved'),
    pg_catalog.jsonb_build_object('user_id', _admin_blocked, 'expected', 'profile_not_approved')
  ] LOOP
    PERFORM pg_catalog.set_config('request.jwt.claim.sub', (_payload->>'user_id')::uuid::text, true);
    EXECUTE 'SET LOCAL ROLE authenticated';
    BEGIN
      PERFORM * FROM public.admin_set_user_status(_target_user, 'approved'::public.user_status, 'should fail');
      EXECUTE 'RESET ROLE';
      RAISE EXCEPTION 'assertion_failed: unauthorized admin_set_user_status succeeded';
    EXCEPTION WHEN OTHERS THEN
      GET STACKED DIAGNOSTICS _message = MESSAGE_TEXT;
      EXECUTE 'RESET ROLE';
      IF _message <> _payload->>'expected' THEN
        RAISE EXCEPTION 'assertion_failed: expected %, got %', _payload->>'expected', _message;
      END IF;
    END;
  END LOOP;

  -- 18-24: approved admin changes status and audit contains full metadata.
  PERFORM pg_catalog.set_config('request.jwt.claim.sub', _admin_approved::text, true);
  EXECUTE 'SET LOCAL ROLE authenticated';
  SELECT result.previous_status, result.new_status, result.audit_log_id, result.changed_at
  INTO _previous_status, _new_status, _audit_id, _changed_at
  FROM public.admin_set_user_status(_target_user, 'approved'::public.user_status, 'Aprovacao manual') AS result;
  EXECUTE 'RESET ROLE';

  IF _previous_status <> 'pending'::public.user_status OR _new_status <> 'approved'::public.user_status THEN
    RAISE EXCEPTION 'assertion_failed: wrong status return %, %', _previous_status, _new_status;
  END IF;

  SELECT aal.payload INTO _payload
  FROM public.admin_audit_logs aal
  WHERE aal.id = _audit_id;

  IF _payload IS NULL
     OR _payload->>'actor_user_id' <> _admin_approved::text
     OR _payload->>'target_user_id' <> _target_user::text
     OR _payload->>'previous_status' <> 'pending'
     OR _payload->>'new_status' <> 'approved'
     OR _payload->>'reason' <> 'Aprovacao manual' THEN
    RAISE EXCEPTION 'assertion_failed: audit payload incomplete: %', _payload;
  END IF;

  PERFORM pg_catalog.set_config('request.jwt.claim.sub', _admin_approved::text, true);
  EXECUTE 'SET LOCAL ROLE authenticated';
  SELECT result.previous_status, result.new_status, result.audit_log_id
  INTO _previous_status, _new_status, _audit_id
  FROM public.admin_set_user_status(_target_user, 'blocked'::public.user_status, 'Bloqueio manual') AS result;
  EXECUTE 'RESET ROLE';

  IF _previous_status <> 'approved'::public.user_status OR _new_status <> 'blocked'::public.user_status THEN
    RAISE EXCEPTION 'assertion_failed: wrong second status return %, %', _previous_status, _new_status;
  END IF;

  -- 25-28: failed calls do not create audit or change any profile.
  SELECT pg_catalog.count(*) INTO _before_count
  FROM public.admin_audit_logs aal
  WHERE aal.admin_id = _admin_approved;

  PERFORM pg_catalog.set_config('request.jwt.claim.sub', _admin_approved::text, true);
  EXECUTE 'SET LOCAL ROLE authenticated';
  BEGIN
    PERFORM * FROM public.admin_set_user_status('00000000-0000-0000-0000-000000019999'::uuid, 'approved'::public.user_status, 'missing target');
    EXECUTE 'RESET ROLE';
    RAISE EXCEPTION 'assertion_failed: missing target status update succeeded';
  EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS _message = MESSAGE_TEXT;
    EXECUTE 'RESET ROLE';
    IF _message <> 'target_profile_not_found' THEN
      RAISE EXCEPTION 'assertion_failed: expected target_profile_not_found, got %', _message;
    END IF;
  END;

  SELECT pg_catalog.count(*) INTO _count
  FROM public.admin_audit_logs aal
  WHERE aal.admin_id = _admin_approved;

  IF _count <> _before_count THEN
    RAISE EXCEPTION 'assertion_failed: failed status update created audit';
  END IF;

  IF (SELECT p.status FROM public.profiles p WHERE p.id = _target_user) <> 'blocked'::public.user_status THEN
    RAISE EXCEPTION 'assertion_failed: failed status update changed target profile';
  END IF;

  -- 29: authenticated cannot insert audit logs directly.
  _blocked := false;
  PERFORM pg_catalog.set_config('request.jwt.claim.sub', _admin_approved::text, true);
  BEGIN
    EXECUTE 'SET LOCAL ROLE authenticated';
    INSERT INTO public.admin_audit_logs (admin_id, action, target_table, target_id, payload)
    VALUES (_admin_approved, 'direct_insert', 'profiles', _target_user, '{}'::jsonb);
    EXECUTE 'RESET ROLE';
  EXCEPTION WHEN OTHERS THEN
    _blocked := true;
    EXECUTE 'RESET ROLE';
  END;

  IF NOT _blocked THEN
    RAISE EXCEPTION 'assertion_failed: authenticated inserted admin_audit_logs directly';
  END IF;

  -- 30: approving more than 6 users remains permitted.
  PERFORM pg_catalog.set_config('request.jwt.claim.sub', _admin_approved::text, true);
  EXECUTE 'SET LOCAL ROLE authenticated';
  FOREACH _target_user IN ARRAY _extra_users LOOP
    PERFORM * FROM public.admin_set_user_status(_target_user, 'approved'::public.user_status, 'bulk approval allowed');
  END LOOP;
  EXECUTE 'RESET ROLE';

  SELECT pg_catalog.count(*) INTO _count
  FROM public.profiles p
  WHERE p.id = ANY(_extra_users)
    AND p.status = 'approved'::public.user_status;

  IF _count <> pg_catalog.array_length(_extra_users, 1) THEN
    RAISE EXCEPTION 'assertion_failed: bulk approval above six was not allowed';
  END IF;

  RAISE NOTICE 'admin_audit_and_game_rls contract test passed';
END $$;

ROLLBACK;

-- Manual Lovable SQL Editor validation after applying the migration:
--
-- SELECT *
-- FROM public.admin_set_user_status(
--   '<TARGET_UUID>',
--   'approved',
--   'Aprovação manual'
-- );
--
-- SELECT *
-- FROM public.admin_audit_logs
-- ORDER BY created_at DESC
-- LIMIT 5;
--
-- To validate policies manually, impersonation must be supported by the
-- environment/session. Do not run impersonation SQL in production unless you
-- understand how that SQL Editor session maps auth.uid().
