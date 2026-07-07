-- Local database contract test for club identity validation, badge catalog,
-- and public.update_club_identity(uuid, text, text, text).
-- Intended for a local Supabase/Postgres database after applying
-- fix_club_identity_and_badges. The script rolls back all fixture data.

BEGIN;

DO $$
DECLARE
  _league_id uuid;
  _badge_01 uuid;
  _badge_02 uuid;
  _badge_03 uuid;
  _owner_setup uuid := '00000000-0000-0000-0000-000000031001'::uuid;
  _owner_active uuid := '00000000-0000-0000-0000-000000031002'::uuid;
  _owner_finished uuid := '00000000-0000-0000-0000-000000031003'::uuid;
  _owner_other uuid := '00000000-0000-0000-0000-000000031004'::uuid;
  _pending_user uuid := '00000000-0000-0000-0000-000000031005'::uuid;
  _blocked_user uuid := '00000000-0000-0000-0000-000000031006'::uuid;
  _admin_approved uuid := '00000000-0000-0000-0000-000000031007'::uuid;
  _admin_pending uuid := '00000000-0000-0000-0000-000000031008'::uuid;
  _admin_blocked uuid := '00000000-0000-0000-0000-000000031009'::uuid;
  _create_user_a uuid := '00000000-0000-0000-0000-000000031010'::uuid;
  _create_user_b uuid := '00000000-0000-0000-0000-000000031011'::uuid;
  _create_user_c uuid := '00000000-0000-0000-0000-000000031012'::uuid;
  _create_user_d uuid := '00000000-0000-0000-0000-000000031013'::uuid;
  _club_setup uuid := '00000000-0000-0000-0000-000000031101'::uuid;
  _club_active uuid := '00000000-0000-0000-0000-000000031102'::uuid;
  _club_finished uuid := '00000000-0000-0000-0000-000000031103'::uuid;
  _club_other uuid := '00000000-0000-0000-0000-000000031104'::uuid;
  _all_users uuid[];
  _created_club uuid;
  _audit_before integer;
  _audit_after integer;
  _name text;
  _normalized text;
  _abbr text;
  _badge uuid;
  _count integer;
  _message text;
  _i integer;
  _raised boolean;
BEGIN
  _all_users := ARRAY[
    _owner_setup,
    _owner_active,
    _owner_finished,
    _owner_other,
    _pending_user,
    _blocked_user,
    _admin_approved,
    _admin_pending,
    _admin_blocked,
    _create_user_a,
    _create_user_b,
    _create_user_c,
    _create_user_d
  ];

  SELECT l.id INTO _league_id
  FROM public.leagues l
  WHERE l.slug = 'bagreleirao';

  IF _league_id IS NULL THEN
    RAISE EXCEPTION 'test_setup_failed: bagreleirao league not found';
  END IF;

  SELECT b.id INTO _badge_01
  FROM public.club_badges b
  WHERE b.code = 'badge-01'
    AND b.is_active;

  SELECT b.id INTO _badge_02
  FROM public.club_badges b
  WHERE b.code = 'badge-02'
    AND b.is_active;

  SELECT b.id INTO _badge_03
  FROM public.club_badges b
  WHERE b.code = 'badge-03'
    AND b.is_active;

  IF _badge_01 IS NULL OR _badge_02 IS NULL OR _badge_03 IS NULL THEN
    RAISE EXCEPTION 'test_setup_failed: expected active badge catalog not found';
  END IF;

  DELETE FROM public.admin_audit_logs aal
  WHERE aal.admin_id = ANY(_all_users)
     OR aal.target_id IN (_club_setup, _club_active, _club_finished, _club_other);

  DELETE FROM public.initial_packs ip
  USING public.clubs c
  WHERE ip.club_id = c.id
    AND c.owner_id = ANY(_all_users);

  DELETE FROM public.wallet_transactions wt
  USING public.clubs c
  WHERE wt.club_id = c.id
    AND c.owner_id = ANY(_all_users);

  DELETE FROM public.clubs c
  WHERE c.id IN (_club_setup, _club_active, _club_finished, _club_other)
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
      'club-identity-' || _i::text || '@example.test',
      'test-password',
      pg_catalog.now(),
      '{"provider":"email","providers":["email"]}'::jsonb,
      pg_catalog.jsonb_build_object('username', 'clubid' || pg_catalog.lpad(_i::text, 2, '0')),
      pg_catalog.now(),
      pg_catalog.now()
    );
  END LOOP;

  UPDATE public.profiles
  SET status = 'approved'::public.user_status
  WHERE id IN (
    _owner_setup,
    _owner_active,
    _owner_finished,
    _owner_other,
    _admin_approved,
    _create_user_a,
    _create_user_b,
    _create_user_c,
    _create_user_d
  );

  UPDATE public.profiles
  SET status = 'pending'::public.user_status
  WHERE id IN (_pending_user, _admin_pending);

  UPDATE public.profiles
  SET status = 'blocked'::public.user_status
  WHERE id IN (_blocked_user, _admin_blocked);

  INSERT INTO public.user_roles (user_id, role)
  VALUES
    (_admin_approved, 'admin'::public.app_role),
    (_admin_pending, 'admin'::public.app_role),
    (_admin_blocked, 'admin'::public.app_role);

  UPDATE public.leagues
  SET status = 'setup'::public.league_status,
      max_clubs = 1000
  WHERE id = _league_id;

  INSERT INTO public.clubs (
    id,
    league_id,
    owner_id,
    name,
    normalized_name,
    abbreviation,
    badge_id,
    balance_cents
  )
  VALUES
    (_club_setup, _league_id, _owner_setup, 'Setup Clube', public.normalize_club_name('Setup Clube'), 'SCL', _badge_01, 0),
    (_club_active, _league_id, _owner_active, 'Active Clube', public.normalize_club_name('Active Clube'), 'ACL', _badge_01, 0),
    (_club_finished, _league_id, _owner_finished, 'Finished Clube', public.normalize_club_name('Finished Clube'), 'FCL', _badge_02, 0),
    (_club_other, _league_id, _owner_other, 'Outro Clube', public.normalize_club_name('Outro Clube'), 'OCL', _badge_03, 0);

  PERFORM set_config('request.jwt.claim.sub', _create_user_a::text, true);
  SELECT public.create_club('  Centro   FC  ', 'cfc', 'badge-01') INTO _created_club;

  SELECT c.name, c.normalized_name, c.abbreviation
  INTO _name, _normalized, _abbr
  FROM public.clubs c
  WHERE c.id = _created_club;

  IF _name <> 'Centro FC' THEN
    RAISE EXCEPTION 'expected trimmed/collapsed club name, got %', _name;
  END IF;
  IF _normalized <> 'centro fc' THEN
    RAISE EXCEPTION 'expected normalized lowercase club name, got %', _normalized;
  END IF;
  IF _abbr <> 'CFC' THEN
    RAISE EXCEPTION 'expected uppercase abbreviation, got %', _abbr;
  END IF;

  PERFORM set_config('request.jwt.claim.sub', _create_user_b::text, true);
  SELECT public.create_club('Açaí Futebol', 'aca', 'badge-02') INTO _created_club;
  SELECT c.normalized_name INTO _normalized FROM public.clubs c WHERE c.id = _created_club;
  IF _normalized <> 'açaí futebol' THEN
    RAISE EXCEPTION 'expected accent-preserving normalized name, got %', _normalized;
  END IF;

  PERFORM set_config('request.jwt.claim.sub', _create_user_c::text, true);
  BEGIN
    PERFORM public.create_club('centro fc', 'CFD', 'badge-03');
    RAISE EXCEPTION 'expected duplicate normalized name to fail';
  EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS _message = MESSAGE_TEXT;
    IF _message <> 'club_name_already_exists' THEN
      RAISE EXCEPTION 'expected club_name_already_exists, got %', _message;
    END IF;
  END;

  PERFORM set_config('request.jwt.claim.sub', _create_user_c::text, true);
  BEGIN
    PERFORM public.create_club('  Centro      FC  ', 'CFE', 'badge-03');
    RAISE EXCEPTION 'expected duplicate spaced name to fail';
  EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS _message = MESSAGE_TEXT;
    IF _message <> 'club_name_already_exists' THEN
      RAISE EXCEPTION 'expected club_name_already_exists for spaced duplicate, got %', _message;
    END IF;
  END;

  BEGIN
    PERFORM public.create_club('A', 'CFA', 'badge-03');
    RAISE EXCEPTION 'expected short name to fail';
  EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS _message = MESSAGE_TEXT;
    IF _message <> 'club_name_invalid_length' THEN
      RAISE EXCEPTION 'expected club_name_invalid_length, got %', _message;
    END IF;
  END;

  BEGIN
    PERFORM public.create_club('Clube Nome Muito Grande ABC', 'CFA', 'badge-03');
    RAISE EXCEPTION 'expected long name to fail';
  EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS _message = MESSAGE_TEXT;
    IF _message <> 'club_name_invalid_length' THEN
      RAISE EXCEPTION 'expected club_name_invalid_length, got %', _message;
    END IF;
  END;

  BEGIN
    PERFORM public.create_club('Bagre_FC', 'CFA', 'badge-03');
    RAISE EXCEPTION 'expected symbol in name to fail';
  EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS _message = MESSAGE_TEXT;
    IF _message <> 'club_name_invalid_characters' THEN
      RAISE EXCEPTION 'expected club_name_invalid_characters, got %', _message;
    END IF;
  END;

  BEGIN
    PERFORM public.create_club('Sigla Curta', 'A', 'badge-03');
    RAISE EXCEPTION 'expected short abbreviation to fail';
  EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS _message = MESSAGE_TEXT;
    IF _message <> 'club_abbreviation_invalid' THEN
      RAISE EXCEPTION 'expected club_abbreviation_invalid, got %', _message;
    END IF;
  END;

  BEGIN
    PERFORM public.create_club('Sigla Longa', 'ABCDE', 'badge-03');
    RAISE EXCEPTION 'expected long abbreviation to fail';
  EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS _message = MESSAGE_TEXT;
    IF _message <> 'club_abbreviation_invalid' THEN
      RAISE EXCEPTION 'expected club_abbreviation_invalid, got %', _message;
    END IF;
  END;

  BEGIN
    PERFORM public.create_club('Sigla Numero', 'B1', 'badge-03');
    RAISE EXCEPTION 'expected numeric abbreviation to fail';
  EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS _message = MESSAGE_TEXT;
    IF _message <> 'club_abbreviation_invalid' THEN
      RAISE EXCEPTION 'expected club_abbreviation_invalid, got %', _message;
    END IF;
  END;

  BEGIN
    PERFORM public.create_club('Sigla Simbolo', 'B-G', 'badge-03');
    RAISE EXCEPTION 'expected symbol abbreviation to fail';
  EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS _message = MESSAGE_TEXT;
    IF _message <> 'club_abbreviation_invalid' THEN
      RAISE EXCEPTION 'expected club_abbreviation_invalid, got %', _message;
    END IF;
  END;

  BEGIN
    PERFORM public.create_club('Sigla Duplicada', 'CFC', 'badge-03');
    RAISE EXCEPTION 'expected duplicate abbreviation to fail';
  EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS _message = MESSAGE_TEXT;
    IF _message <> 'club_abbreviation_already_exists' THEN
      RAISE EXCEPTION 'expected club_abbreviation_already_exists, got %', _message;
    END IF;
  END;

  BEGIN
    PERFORM public.create_club('Badge Inexistente', 'BIN', 'badge-9999');
    RAISE EXCEPTION 'expected missing badge to fail';
  EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS _message = MESSAGE_TEXT;
    IF _message <> 'club_badge_not_found' THEN
      RAISE EXCEPTION 'expected club_badge_not_found, got %', _message;
    END IF;
  END;

  UPDATE public.club_badges SET is_active = false WHERE code = 'badge-03';
  BEGIN
    PERFORM public.create_club('Badge Inativo', 'BAI', 'badge-03');
    RAISE EXCEPTION 'expected inactive badge to fail';
  EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS _message = MESSAGE_TEXT;
    IF _message <> 'club_badge_inactive' THEN
      RAISE EXCEPTION 'expected club_badge_inactive, got %', _message;
    END IF;
  END;
  UPDATE public.club_badges SET is_active = true WHERE code = 'badge-03';

  PERFORM set_config('request.jwt.claim.sub', _owner_setup::text, true);
  SELECT name, normalized_name, abbreviation, badge_id
  INTO _name, _normalized, _abbr, _badge
  FROM public.update_club_identity(_club_setup, '  Dono   Setup  ', 'dsu', 'badge-02');
  IF _name <> 'Dono Setup' OR _normalized <> 'dono setup' OR _abbr <> 'DSU' OR _badge <> _badge_02 THEN
    RAISE EXCEPTION 'expected owner update during setup to normalize all fields';
  END IF;

  UPDATE public.leagues SET status = 'active'::public.league_status WHERE id = _league_id;
  PERFORM set_config('request.jwt.claim.sub', _owner_active::text, true);
  BEGIN
    PERFORM public.update_club_identity(_club_active, 'Owner Active', NULL, NULL);
    RAISE EXCEPTION 'expected owner update during active to fail';
  EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS _message = MESSAGE_TEXT;
    IF _message <> 'club_identity_locked' THEN
      RAISE EXCEPTION 'expected club_identity_locked, got %', _message;
    END IF;
  END;

  UPDATE public.leagues SET status = 'finished'::public.league_status WHERE id = _league_id;
  PERFORM set_config('request.jwt.claim.sub', _owner_finished::text, true);
  BEGIN
    PERFORM public.update_club_identity(_club_finished, 'Owner Finished', NULL, NULL);
    RAISE EXCEPTION 'expected owner update during finished to fail';
  EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS _message = MESSAGE_TEXT;
    IF _message <> 'club_identity_locked' THEN
      RAISE EXCEPTION 'expected club_identity_locked for finished, got %', _message;
    END IF;
  END;

  UPDATE public.leagues SET status = 'setup'::public.league_status WHERE id = _league_id;
  PERFORM set_config('request.jwt.claim.sub', _owner_other::text, true);
  BEGIN
    PERFORM public.update_club_identity(_club_setup, 'Non Owner', NULL, NULL);
    RAISE EXCEPTION 'expected non-owner update to fail';
  EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS _message = MESSAGE_TEXT;
    IF _message <> 'forbidden_not_club_owner' THEN
      RAISE EXCEPTION 'expected forbidden_not_club_owner, got %', _message;
    END IF;
  END;

  PERFORM set_config('request.jwt.claim.sub', _pending_user::text, true);
  BEGIN
    PERFORM public.update_club_identity(_club_setup, 'Pending Clube', NULL, NULL);
    RAISE EXCEPTION 'expected pending user update to fail';
  EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS _message = MESSAGE_TEXT;
    IF _message <> 'profile_not_approved' THEN
      RAISE EXCEPTION 'expected profile_not_approved for pending, got %', _message;
    END IF;
  END;

  PERFORM set_config('request.jwt.claim.sub', _blocked_user::text, true);
  BEGIN
    PERFORM public.update_club_identity(_club_setup, 'Blocked Clube', NULL, NULL);
    RAISE EXCEPTION 'expected blocked user update to fail';
  EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS _message = MESSAGE_TEXT;
    IF _message <> 'profile_not_approved' THEN
      RAISE EXCEPTION 'expected profile_not_approved for blocked, got %', _message;
    END IF;
  END;

  UPDATE public.leagues SET status = 'active'::public.league_status WHERE id = _league_id;
  PERFORM set_config('request.jwt.claim.sub', _admin_approved::text, true);
  SELECT COUNT(*) INTO _audit_before
  FROM public.admin_audit_logs
  WHERE action = 'admin_update_club_identity'
    AND target_id = _club_active;

  PERFORM public.update_club_identity(_club_active, 'Admin Active', 'AAD', 'badge-02');
  SELECT COUNT(*) INTO _audit_after
  FROM public.admin_audit_logs
  WHERE action = 'admin_update_club_identity'
    AND target_id = _club_active;
  IF _audit_after <> _audit_before + 1 THEN
    RAISE EXCEPTION 'expected admin update audit during active';
  END IF;

  UPDATE public.leagues SET status = 'finished'::public.league_status WHERE id = _league_id;
  PERFORM public.update_club_identity(_club_finished, 'Admin Finished', 'AFD', 'badge-01');

  PERFORM set_config('request.jwt.claim.sub', _admin_pending::text, true);
  BEGIN
    PERFORM public.update_club_identity(_club_setup, 'Pending Admin', NULL, NULL);
    RAISE EXCEPTION 'expected pending admin to fail';
  EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS _message = MESSAGE_TEXT;
    IF _message <> 'profile_not_approved' THEN
      RAISE EXCEPTION 'expected profile_not_approved for pending admin, got %', _message;
    END IF;
  END;

  PERFORM set_config('request.jwt.claim.sub', _admin_blocked::text, true);
  BEGIN
    PERFORM public.update_club_identity(_club_setup, 'Blocked Admin', NULL, NULL);
    RAISE EXCEPTION 'expected blocked admin to fail';
  EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS _message = MESSAGE_TEXT;
    IF _message <> 'profile_not_approved' THEN
      RAISE EXCEPTION 'expected profile_not_approved for blocked admin, got %', _message;
    END IF;
  END;

  UPDATE public.leagues SET status = 'setup'::public.league_status WHERE id = _league_id;
  PERFORM set_config('request.jwt.claim.sub', _owner_setup::text, true);
  SELECT abbreviation, badge_id
  INTO _abbr, _badge
  FROM public.update_club_identity(_club_setup, 'Parcial Dono', NULL, NULL);
  IF _abbr <> 'DSU' OR _badge <> _badge_02 THEN
    RAISE EXCEPTION 'expected partial update to preserve omitted fields';
  END IF;

  BEGIN
    PERFORM public.update_club_identity(_club_setup, NULL, NULL, NULL);
    RAISE EXCEPTION 'expected no-change call to fail';
  EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS _message = MESSAGE_TEXT;
    IF _message <> 'no_changes_provided' THEN
      RAISE EXCEPTION 'expected no_changes_provided, got %', _message;
    END IF;
  END;

  BEGIN
    PERFORM public.update_club_identity(_club_setup, 'Parcial Dono', 'DSU', 'badge-02');
    RAISE EXCEPTION 'expected effective no-change call to fail';
  EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS _message = MESSAGE_TEXT;
    IF _message <> 'no_changes_provided' THEN
      RAISE EXCEPTION 'expected no_changes_provided for identical values, got %', _message;
    END IF;
  END;

  _raised := false;
  BEGIN
    SET LOCAL ROLE authenticated;
    UPDATE public.clubs SET name = 'Direto Falhou' WHERE id = _club_setup;
    RESET ROLE;
  EXCEPTION WHEN OTHERS THEN
    RESET ROLE;
    _raised := true;
  END;
  IF NOT _raised THEN
    RAISE EXCEPTION 'expected direct UPDATE on clubs to fail';
  END;

  SELECT COUNT(*) INTO _count
  FROM public.clubs c
  WHERE c.badge_id = _badge_02;
  IF _count < 2 THEN
    RAISE EXCEPTION 'expected badge sharing between clubs';
  END IF;

  PERFORM set_config('request.jwt.claim.sub', _create_user_d::text, true);
  SELECT public.create_club('Pacote Saldo', 'PSL', 'badge-01') INTO _created_club;
  IF NOT EXISTS (
    SELECT 1
    FROM public.wallet_transactions wt
    WHERE wt.club_id = _created_club
      AND wt.amount_cents = 1000
      AND wt.kind = 'initial_credit'::public.wallet_transaction_type
  ) THEN
    RAISE EXCEPTION 'expected create_club initial wallet credit';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM public.initial_packs ip WHERE ip.club_id = _created_club) THEN
    RAISE EXCEPTION 'expected create_club initial pack';
  END IF;

  PERFORM set_config('request.jwt.claim.sub', _admin_approved::text, true);
  SELECT c.name INTO _name FROM public.clubs c WHERE c.id = _club_other;
  ALTER TABLE public.admin_audit_logs
    ADD CONSTRAINT admin_audit_test_reject_club_identity
    CHECK (action <> 'admin_update_club_identity')
    NOT VALID;
  _raised := false;
  BEGIN
    PERFORM public.update_club_identity(_club_other, 'Audit Rollback', NULL, NULL);
  EXCEPTION WHEN OTHERS THEN
    _raised := true;
  END;
  ALTER TABLE public.admin_audit_logs
    DROP CONSTRAINT admin_audit_test_reject_club_identity;
  IF NOT _raised THEN
    RAISE EXCEPTION 'expected audit failure to rollback club update';
  END IF;
  IF EXISTS (
    SELECT 1
    FROM public.clubs c
    WHERE c.id = _club_other
      AND c.name = 'Audit Rollback'
  ) THEN
    RAISE EXCEPTION 'expected club update rollback when audit insert fails';
  END IF;
END;
$$;

ROLLBACK;
