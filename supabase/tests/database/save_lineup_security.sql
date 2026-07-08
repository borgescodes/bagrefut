-- Local database contract test for public.save_lineup(...).
-- Intended for a local Supabase/Postgres database after applying the
-- fix_lineup_security migration. The script rolls back all fixture data.

BEGIN;

DO $$
DECLARE
  _league_id uuid;
  _badge_id uuid;
  _owner_user_id uuid := '00000000-0000-0000-0000-000000009101'::uuid;
  _other_user_id uuid := '00000000-0000-0000-0000-000000009102'::uuid;
  _pending_user_id uuid := '00000000-0000-0000-0000-000000009103'::uuid;
  _blocked_user_id uuid := '00000000-0000-0000-0000-000000009104'::uuid;
  _owner_club_id uuid := '00000000-0000-0000-0000-000000009201'::uuid;
  _other_club_id uuid := '00000000-0000-0000-0000-000000009202'::uuid;
  _pending_club_id uuid := '00000000-0000-0000-0000-000000009203'::uuid;
  _blocked_club_id uuid := '00000000-0000-0000-0000-000000009204'::uuid;
  _season_id uuid := '00000000-0000-0000-0000-000000009301'::uuid;
  _round_id uuid := '00000000-0000-0000-0000-000000009401'::uuid;
  _locked_round_id uuid := '00000000-0000-0000-0000-000000009402'::uuid;
  _owner_cards uuid[] := ARRAY[]::uuid[];
  _other_cards uuid[] := ARRAY[]::uuid[];
  _lineup_id uuid;
  _previous_lineup_id uuid;
  _count integer;
  _starters integer;
  _message text;
  _payload jsonb;
  _improvised_payload jsonb;
  _dml_blocked boolean;
  _i integer;
  _player_id uuid;
  _club_player_id uuid;
BEGIN
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

  DELETE FROM public.lineup_players lp
  USING public.lineups l
  WHERE lp.lineup_id = l.id
    AND l.club_id IN (_owner_club_id, _other_club_id, _pending_club_id, _blocked_club_id);

  DELETE FROM public.lineups l
  WHERE l.club_id IN (_owner_club_id, _other_club_id, _pending_club_id, _blocked_club_id);

  DELETE FROM public.rounds r
  WHERE r.id IN (_round_id, _locked_round_id);

  DELETE FROM public.seasons s
  WHERE s.id = _season_id;

  DELETE FROM public.club_players cp
  WHERE cp.club_id IN (_owner_club_id, _other_club_id, _pending_club_id, _blocked_club_id)
     OR cp.player_id IN (SELECT p.id FROM public.players p WHERE p.code LIKE 'BFLINEUP-%');

  DELETE FROM public.players p
  WHERE p.code LIKE 'BFLINEUP-%';

  DELETE FROM public.clubs c
  WHERE c.id IN (_owner_club_id, _other_club_id, _pending_club_id, _blocked_club_id);

  DELETE FROM public.profiles p
  WHERE p.id IN (_owner_user_id, _other_user_id, _pending_user_id, _blocked_user_id);

  DELETE FROM auth.users u
  WHERE u.id IN (_owner_user_id, _other_user_id, _pending_user_id, _blocked_user_id);

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
  VALUES
    (_owner_user_id, '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'lineup-owner@example.test', 'test-password', pg_catalog.now(), '{"provider":"email","providers":["email"]}'::jsonb, '{"username":"lineupown"}'::jsonb, pg_catalog.now(), pg_catalog.now()),
    (_other_user_id, '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'lineup-other@example.test', 'test-password', pg_catalog.now(), '{"provider":"email","providers":["email"]}'::jsonb, '{"username":"lineupoth"}'::jsonb, pg_catalog.now(), pg_catalog.now()),
    (_pending_user_id, '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'lineup-pending@example.test', 'test-password', pg_catalog.now(), '{"provider":"email","providers":["email"]}'::jsonb, '{"username":"lineuppend"}'::jsonb, pg_catalog.now(), pg_catalog.now()),
    (_blocked_user_id, '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'lineup-blocked@example.test', 'test-password', pg_catalog.now(), '{"provider":"email","providers":["email"]}'::jsonb, '{"username":"lineupblk"}'::jsonb, pg_catalog.now(), pg_catalog.now());

  UPDATE public.profiles
  SET status = 'approved'::public.user_status
  WHERE id IN (_owner_user_id, _other_user_id);

  UPDATE public.profiles
  SET status = 'pending'::public.user_status
  WHERE id = _pending_user_id;

  UPDATE public.profiles
  SET status = 'blocked'::public.user_status
  WHERE id = _blocked_user_id;

  INSERT INTO public.clubs (id, league_id, owner_id, name, normalized_name, abbreviation, badge_id, balance_cents)
  VALUES
    (_owner_club_id, _league_id, _owner_user_id, 'Lineup Owner', public.normalize_club_name('Lineup Owner'), 'LOW', _badge_id, 0),
    (_other_club_id, _league_id, _other_user_id, 'Lineup Other', public.normalize_club_name('Lineup Other'), 'LOT', _badge_id, 0),
    (_pending_club_id, _league_id, _pending_user_id, 'Lineup Pending', public.normalize_club_name('Lineup Pending'), 'LPE', _badge_id, 0),
    (_blocked_club_id, _league_id, _blocked_user_id, 'Lineup Blocked', public.normalize_club_name('Lineup Blocked'), 'LBL', _badge_id, 0);

  INSERT INTO public.seasons (id, league_id, season_number, status, started_at)
  VALUES (_season_id, _league_id, 9101, 'active', pg_catalog.now());

  INSERT INTO public.rounds (id, season_id, round_number, lineup_lock_at, starts_at, ends_at)
  VALUES
    (_round_id, _season_id, 1, pg_catalog.now() + interval '1 day', pg_catalog.now() + interval '2 days', pg_catalog.now() + interval '3 days'),
    (_locked_round_id, _season_id, 2, pg_catalog.now() - interval '1 minute', pg_catalog.now() + interval '1 day', pg_catalog.now() + interval '2 days');

  FOR _i IN 1..12 LOOP
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
      'BFLINEUP-O-' || pg_catalog.lpad(_i::text, 2, '0'),
      'Lineup Owner Card ' || _i::text,
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
    )
    RETURNING id INTO _player_id;

    SELECT cp.id INTO _club_player_id
    FROM public.club_players cp
    WHERE cp.player_id = _player_id
    FOR UPDATE;

    DELETE FROM public.system_market_stock sms
    WHERE sms.club_player_id = _club_player_id;

    UPDATE public.club_players
    SET club_id = _owner_club_id,
        is_reserved = false
    WHERE id = _club_player_id;

    _owner_cards := _owner_cards || _club_player_id;
  END LOOP;

  FOR _i IN 1..6 LOOP
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
      'BFLINEUP-X-' || pg_catalog.lpad(_i::text, 2, '0'),
      'Lineup Other Card ' || _i::text,
      'DEF'::public.player_position,
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
    )
    RETURNING id INTO _player_id;

    SELECT cp.id INTO _club_player_id
    FROM public.club_players cp
    WHERE cp.player_id = _player_id
    FOR UPDATE;

    DELETE FROM public.system_market_stock sms
    WHERE sms.club_player_id = _club_player_id;

    UPDATE public.club_players
    SET club_id = _other_club_id,
        is_reserved = false
    WHERE id = _club_player_id;

    _other_cards := _other_cards || _club_player_id;
  END LOOP;

  UPDATE public.club_players
  SET is_reserved = true
  WHERE id = _owner_cards[12];

  _payload := pg_catalog.jsonb_build_array(
    pg_catalog.jsonb_build_object('club_player_id', _owner_cards[1], 'slot_position', 'GK', 'is_starter', true, 'slot_index', 1),
    pg_catalog.jsonb_build_object('club_player_id', _owner_cards[2], 'slot_position', 'DEF', 'is_starter', true, 'slot_index', 1),
    pg_catalog.jsonb_build_object('club_player_id', _owner_cards[3], 'slot_position', 'DEF', 'is_starter', true, 'slot_index', 2),
    pg_catalog.jsonb_build_object('club_player_id', _owner_cards[4], 'slot_position', 'MID', 'is_starter', true, 'slot_index', 1),
    pg_catalog.jsonb_build_object('club_player_id', _owner_cards[5], 'slot_position', 'ATA', 'is_starter', true, 'slot_index', 1),
    pg_catalog.jsonb_build_object('club_player_id', _owner_cards[6], 'slot_position', 'GK', 'is_starter', false, 'slot_index', 2),
    pg_catalog.jsonb_build_object('club_player_id', _owner_cards[7], 'slot_position', 'DEF', 'is_starter', false, 'slot_index', 3),
    pg_catalog.jsonb_build_object('club_player_id', _owner_cards[8], 'slot_position', 'MID', 'is_starter', false, 'slot_index', 2),
    pg_catalog.jsonb_build_object('club_player_id', _owner_cards[9], 'slot_position', 'ATA', 'is_starter', false, 'slot_index', 2),
    pg_catalog.jsonb_build_object('club_player_id', _owner_cards[10], 'slot_position', 'ATA', 'is_starter', false, 'slot_index', 3)
  );

  _improvised_payload := _payload;

  PERFORM pg_catalog.set_config('request.jwt.claim.sub', _owner_user_id::text, true);

  SELECT result.lineup_id INTO _lineup_id
  FROM public.save_lineup(_round_id, '1-2-1-1'::public.formation, 'balanced'::public.play_style, _payload) AS result;

  IF _lineup_id IS NULL THEN
    RAISE EXCEPTION 'assertion_failed: valid owner save returned no lineup_id';
  END IF;

  SELECT pg_catalog.count(*), pg_catalog.count(*) FILTER (WHERE lp.is_starter)
  INTO _count, _starters
  FROM public.lineup_players lp
  WHERE lp.lineup_id = _lineup_id;

  IF _count <> 10 OR _starters <> 5 THEN
    RAISE EXCEPTION 'assertion_failed: expected 10 players and 5 starters, got %, %', _count, _starters;
  END IF;

  -- Improviso is allowed: all owner test cards have natural position ATA,
  -- but the valid payload uses GK/DEF/MID slots.
  SELECT result.lineup_id INTO _lineup_id
  FROM public.save_lineup(_round_id, '1-2-1-1'::public.formation, 'offensive'::public.play_style, _improvised_payload) AS result;

  -- Second save replaces the previous lineup_players set.
  _previous_lineup_id := _lineup_id;
  SELECT result.lineup_id INTO _lineup_id
  FROM public.save_lineup(
    _round_id,
    '1-1-2-1'::public.formation,
    'defensive'::public.play_style,
    pg_catalog.jsonb_build_array(
      pg_catalog.jsonb_build_object('club_player_id', _owner_cards[1], 'slot_position', 'GK', 'is_starter', true, 'slot_index', 1),
      pg_catalog.jsonb_build_object('club_player_id', _owner_cards[2], 'slot_position', 'DEF', 'is_starter', true, 'slot_index', 1),
      pg_catalog.jsonb_build_object('club_player_id', _owner_cards[3], 'slot_position', 'MID', 'is_starter', true, 'slot_index', 1),
      pg_catalog.jsonb_build_object('club_player_id', _owner_cards[4], 'slot_position', 'MID', 'is_starter', true, 'slot_index', 2),
      pg_catalog.jsonb_build_object('club_player_id', _owner_cards[5], 'slot_position', 'ATA', 'is_starter', true, 'slot_index', 1)
    )
  ) AS result;

  IF _lineup_id <> _previous_lineup_id THEN
    RAISE EXCEPTION 'assertion_failed: second save created a different lineup';
  END IF;

  SELECT pg_catalog.count(*) INTO _count
  FROM public.lineup_players lp
  WHERE lp.lineup_id = _lineup_id;

  IF _count <> 5 THEN
    RAISE EXCEPTION 'assertion_failed: second save did not replace old players, got %', _count;
  END IF;

  BEGIN
    PERFORM * FROM public.save_lineup(
      _round_id,
      '1-1-2-1'::public.formation,
      'balanced'::public.play_style,
      pg_catalog.jsonb_build_array(
        pg_catalog.jsonb_build_object('club_player_id', _owner_cards[1], 'slot_position', 'GK', 'is_starter', true, 'slot_index', 1),
        pg_catalog.jsonb_build_object('club_player_id', _owner_cards[2], 'slot_position', 'DEF', 'is_starter', true, 'slot_index', 1),
        pg_catalog.jsonb_build_object('club_player_id', _owner_cards[3], 'slot_position', 'MID', 'is_starter', true, 'slot_index', 1),
        pg_catalog.jsonb_build_object('club_player_id', _owner_cards[4], 'slot_position', 'MID', 'is_starter', true, 'slot_index', 2)
      )
    );
    RAISE EXCEPTION 'assertion_failed: fewer than 5 starters succeeded';
  EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS _message = MESSAGE_TEXT;
    IF _message <> 'invalid_player_count' THEN
      RAISE EXCEPTION 'assertion_failed: expected invalid_player_count, got %', _message;
    END IF;
  END;

  BEGIN
    PERFORM * FROM public.save_lineup(
      _round_id,
      '1-1-2-1'::public.formation,
      'balanced'::public.play_style,
      pg_catalog.jsonb_build_array(
        pg_catalog.jsonb_build_object('club_player_id', _owner_cards[1], 'slot_position', 'GK', 'is_starter', true, 'slot_index', 1),
        pg_catalog.jsonb_build_object('club_player_id', _owner_cards[1], 'slot_position', 'DEF', 'is_starter', true, 'slot_index', 1),
        pg_catalog.jsonb_build_object('club_player_id', _owner_cards[3], 'slot_position', 'MID', 'is_starter', true, 'slot_index', 1),
        pg_catalog.jsonb_build_object('club_player_id', _owner_cards[4], 'slot_position', 'MID', 'is_starter', true, 'slot_index', 2),
        pg_catalog.jsonb_build_object('club_player_id', _owner_cards[5], 'slot_position', 'ATA', 'is_starter', true, 'slot_index', 1)
      )
    );
    RAISE EXCEPTION 'assertion_failed: duplicate player succeeded';
  EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS _message = MESSAGE_TEXT;
    IF _message <> 'duplicate_club_player' THEN
      RAISE EXCEPTION 'assertion_failed: expected duplicate_club_player, got %', _message;
    END IF;
  END;

  BEGIN
    PERFORM * FROM public.save_lineup(
      _round_id,
      '1-1-2-1'::public.formation,
      'balanced'::public.play_style,
      pg_catalog.jsonb_build_array(
        pg_catalog.jsonb_build_object('club_player_id', _owner_cards[1], 'slot_position', 'GK', 'is_starter', true, 'slot_index', 1),
        pg_catalog.jsonb_build_object('club_player_id', _owner_cards[2], 'slot_position', 'DEF', 'is_starter', true, 'slot_index', 1),
        pg_catalog.jsonb_build_object('club_player_id', _owner_cards[3], 'slot_position', 'MID', 'is_starter', true, 'slot_index', 1),
        pg_catalog.jsonb_build_object('club_player_id', _owner_cards[4], 'slot_position', 'MID', 'is_starter', true, 'slot_index', 1),
        pg_catalog.jsonb_build_object('club_player_id', _owner_cards[5], 'slot_position', 'ATA', 'is_starter', true, 'slot_index', 1)
      )
    );
    RAISE EXCEPTION 'assertion_failed: duplicate slot succeeded';
  EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS _message = MESSAGE_TEXT;
    IF _message <> 'duplicate_slot' THEN
      RAISE EXCEPTION 'assertion_failed: expected duplicate_slot, got %', _message;
    END IF;
  END;

  BEGIN
    PERFORM * FROM public.save_lineup(
      _round_id,
      '1-2-1-1'::public.formation,
      'balanced'::public.play_style,
      pg_catalog.jsonb_build_array(
        pg_catalog.jsonb_build_object('club_player_id', _owner_cards[1], 'slot_position', 'GK', 'is_starter', true, 'slot_index', 1),
        pg_catalog.jsonb_build_object('club_player_id', _other_cards[1], 'slot_position', 'DEF', 'is_starter', true, 'slot_index', 1),
        pg_catalog.jsonb_build_object('club_player_id', _owner_cards[3], 'slot_position', 'DEF', 'is_starter', true, 'slot_index', 2),
        pg_catalog.jsonb_build_object('club_player_id', _owner_cards[4], 'slot_position', 'MID', 'is_starter', true, 'slot_index', 1),
        pg_catalog.jsonb_build_object('club_player_id', _owner_cards[5], 'slot_position', 'ATA', 'is_starter', true, 'slot_index', 1)
      )
    );
    RAISE EXCEPTION 'assertion_failed: other club card succeeded';
  EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS _message = MESSAGE_TEXT;
    IF _message <> 'club_player_not_owned' THEN
      RAISE EXCEPTION 'assertion_failed: expected club_player_not_owned, got %', _message;
    END IF;
  END;

  BEGIN
    PERFORM * FROM public.save_lineup(
      _round_id,
      '1-2-1-1'::public.formation,
      'balanced'::public.play_style,
      pg_catalog.jsonb_build_array(
        pg_catalog.jsonb_build_object('club_player_id', _owner_cards[1], 'slot_position', 'GK', 'is_starter', true, 'slot_index', 1),
        pg_catalog.jsonb_build_object('club_player_id', _owner_cards[2], 'slot_position', 'DEF', 'is_starter', true, 'slot_index', 1),
        pg_catalog.jsonb_build_object('club_player_id', _owner_cards[3], 'slot_position', 'DEF', 'is_starter', true, 'slot_index', 2),
        pg_catalog.jsonb_build_object('club_player_id', _owner_cards[4], 'slot_position', 'MID', 'is_starter', true, 'slot_index', 1),
        pg_catalog.jsonb_build_object('club_player_id', _owner_cards[12], 'slot_position', 'ATA', 'is_starter', true, 'slot_index', 1)
      )
    );
    RAISE EXCEPTION 'assertion_failed: reserved card succeeded';
  EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS _message = MESSAGE_TEXT;
    IF _message <> 'club_player_reserved' THEN
      RAISE EXCEPTION 'assertion_failed: expected club_player_reserved, got %', _message;
    END IF;
  END;

  PERFORM pg_catalog.set_config('request.jwt.claim.sub', _pending_user_id::text, true);
  BEGIN
    PERFORM * FROM public.save_lineup(_round_id, '1-2-1-1'::public.formation, 'balanced'::public.play_style, _payload);
    RAISE EXCEPTION 'assertion_failed: pending user succeeded';
  EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS _message = MESSAGE_TEXT;
    IF _message <> 'profile_not_approved' THEN
      RAISE EXCEPTION 'assertion_failed: expected profile_not_approved for pending, got %', _message;
    END IF;
  END;

  PERFORM pg_catalog.set_config('request.jwt.claim.sub', _blocked_user_id::text, true);
  BEGIN
    PERFORM * FROM public.save_lineup(_round_id, '1-2-1-1'::public.formation, 'balanced'::public.play_style, _payload);
    RAISE EXCEPTION 'assertion_failed: blocked user succeeded';
  EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS _message = MESSAGE_TEXT;
    IF _message <> 'profile_not_approved' THEN
      RAISE EXCEPTION 'assertion_failed: expected profile_not_approved for blocked, got %', _message;
    END IF;
  END;

  PERFORM pg_catalog.set_config('request.jwt.claim.sub', _owner_user_id::text, true);
  BEGIN
    PERFORM * FROM public.save_lineup(
      _round_id,
      '1-2-1-1'::public.formation,
      'balanced'::public.play_style,
      pg_catalog.jsonb_build_array(
        pg_catalog.jsonb_build_object('club_player_id', _owner_cards[1], 'slot_position', 'GK', 'is_starter', true, 'slot_index', 1),
        pg_catalog.jsonb_build_object('club_player_id', _owner_cards[2], 'slot_position', 'DEF', 'is_starter', true, 'slot_index', 1),
        pg_catalog.jsonb_build_object('club_player_id', _owner_cards[3], 'slot_position', 'MID', 'is_starter', true, 'slot_index', 1),
        pg_catalog.jsonb_build_object('club_player_id', _owner_cards[4], 'slot_position', 'MID', 'is_starter', true, 'slot_index', 2),
        pg_catalog.jsonb_build_object('club_player_id', _owner_cards[5], 'slot_position', 'ATA', 'is_starter', true, 'slot_index', 1)
      )
    );
    RAISE EXCEPTION 'assertion_failed: incompatible formation succeeded';
  EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS _message = MESSAGE_TEXT;
    IF _message <> 'formation_slot_mismatch' THEN
      RAISE EXCEPTION 'assertion_failed: expected formation_slot_mismatch, got %', _message;
    END IF;
  END;

  BEGIN
    PERFORM * FROM public.save_lineup(_locked_round_id, '1-2-1-1'::public.formation, 'balanced'::public.play_style, _payload);
    RAISE EXCEPTION 'assertion_failed: locked round save succeeded';
  EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS _message = MESSAGE_TEXT;
    IF _message <> 'lineup_locked' THEN
      RAISE EXCEPTION 'assertion_failed: expected lineup_locked, got %', _message;
    END IF;
  END;

  -- Error rollback: invalid save after an existing lineup must leave the previous lineup intact.
  SELECT pg_catalog.count(*) INTO _count
  FROM public.lineup_players lp
  WHERE lp.lineup_id = _lineup_id;

  BEGIN
    PERFORM * FROM public.save_lineup(
      _round_id,
      '1-1-2-1'::public.formation,
      'balanced'::public.play_style,
      pg_catalog.jsonb_build_array(
        pg_catalog.jsonb_build_object('club_player_id', _owner_cards[1], 'slot_position', 'GK', 'is_starter', true, 'slot_index', 1),
        pg_catalog.jsonb_build_object('club_player_id', _owner_cards[2], 'slot_position', 'DEF', 'is_starter', true, 'slot_index', 1),
        pg_catalog.jsonb_build_object('club_player_id', _owner_cards[3], 'slot_position', 'MID', 'is_starter', true, 'slot_index', 1),
        pg_catalog.jsonb_build_object('club_player_id', _owner_cards[4], 'slot_position', 'MID', 'is_starter', true, 'slot_index', 1),
        pg_catalog.jsonb_build_object('club_player_id', _owner_cards[5], 'slot_position', 'ATA', 'is_starter', true, 'slot_index', 1)
      )
    );
  EXCEPTION WHEN OTHERS THEN
    NULL;
  END;

  IF (SELECT pg_catalog.count(*) FROM public.lineup_players lp WHERE lp.lineup_id = _lineup_id) <> _count THEN
    RAISE EXCEPTION 'assertion_failed: failed save changed existing lineup_players';
  END IF;

  _dml_blocked := false;
  BEGIN
    EXECUTE 'SET LOCAL ROLE authenticated';
    INSERT INTO public.lineups (club_id, round_id, formation, play_style)
    VALUES (_owner_club_id, _round_id, '1-2-1-1'::public.formation, 'balanced'::public.play_style);
    EXECUTE 'RESET ROLE';
  EXCEPTION WHEN OTHERS THEN
    _dml_blocked := true;
    EXECUTE 'RESET ROLE';
  END;

  IF NOT _dml_blocked THEN
    RAISE EXCEPTION 'assertion_failed: direct DML on lineups succeeded';
  END IF;

  _dml_blocked := false;
  BEGIN
    EXECUTE 'SET LOCAL ROLE authenticated';
    DELETE FROM public.lineup_players
    WHERE lineup_id = _lineup_id;
    EXECUTE 'RESET ROLE';
  EXCEPTION WHEN OTHERS THEN
    _dml_blocked := true;
    EXECUTE 'RESET ROLE';
  END;

  IF NOT _dml_blocked THEN
    RAISE EXCEPTION 'assertion_failed: direct DML on lineup_players succeeded';
  END IF;

  RAISE NOTICE 'save_lineup_security contract test passed';
END $$;

ROLLBACK;
