-- Local database contract test for match simulation RPCs.
-- Intended for a local Supabase/Postgres database after applying the
-- match simulation migration. The script rolls back all fixture data.

BEGIN;

DO $$
DECLARE
  _league_id uuid;
  _badge_id uuid;
  _admin_user uuid := '00000000-0000-0000-0000-000000061001'::uuid;
  _regular_user uuid := '00000000-0000-0000-0000-000000061002'::uuid;
  _users uuid[] := ARRAY[
    '00000000-0000-0000-0000-000000061001'::uuid,
    '00000000-0000-0000-0000-000000061002'::uuid,
    '00000000-0000-0000-0000-000000061003'::uuid,
    '00000000-0000-0000-0000-000000061004'::uuid,
    '00000000-0000-0000-0000-000000061005'::uuid,
    '00000000-0000-0000-0000-000000061006'::uuid
  ];
  _clubs uuid[] := ARRAY[
    '00000000-0000-0000-0000-000000061101'::uuid,
    '00000000-0000-0000-0000-000000061102'::uuid,
    '00000000-0000-0000-0000-000000061103'::uuid,
    '00000000-0000-0000-0000-000000061104'::uuid,
    '00000000-0000-0000-0000-000000061105'::uuid,
    '00000000-0000-0000-0000-000000061106'::uuid
  ];
  _season_id uuid := '00000000-0000-0000-0000-000000061201'::uuid;
  _round_id uuid := '00000000-0000-0000-0000-000000061301'::uuid;
  _blocked_match_id uuid := '00000000-0000-0000-0000-000000061404'::uuid;
  _match_id uuid;
  _manual_cards uuid[] := ARRAY[]::uuid[];
  _card_id uuid;
  _player_id uuid;
  _payload jsonb;
  _first jsonb;
  _second jsonb;
  _round_result jsonb;
  _message text;
  _event_count integer;
  _snapshot_count integer;
  _reward_count integer;
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
  DELETE FROM public.rounds WHERE id = _round_id;
  DELETE FROM public.season_participants WHERE season_id = _season_id;
  DELETE FROM public.seasons WHERE id = _season_id;
  DELETE FROM public.club_player_attribute_progress cpp
  USING public.club_players cp
  WHERE cpp.club_player_id = cp.id
    AND (cp.club_id = ANY(_clubs) OR cp.player_id IN (SELECT id FROM public.players WHERE code LIKE 'BFMS-%'));
  DELETE FROM public.club_players
  WHERE club_id = ANY(_clubs)
     OR player_id IN (SELECT id FROM public.players WHERE code LIKE 'BFMS-%');
  DELETE FROM public.players WHERE code LIKE 'BFMS-%';
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
      'match-sim-' || _i::text || '@example.test',
      'test-password',
      pg_catalog.now(),
      '{"provider":"email","providers":["email"]}'::jsonb,
      pg_catalog.jsonb_build_object('username', 'msim' || pg_catalog.lpad(_i::text, 2, '0')),
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
      'Match Sim Club ' || _i::text,
      public.normalize_club_name('Match Sim Club ' || _i::text),
      'M' || pg_catalog.lpad(_i::text, 2, '0'),
      _badge_id,
      0,
      true
    );
  END LOOP;

  UPDATE public.profiles SET status = 'approved'::public.user_status WHERE id = ANY(_users);
  INSERT INTO public.user_roles(user_id, role) VALUES (_admin_user, 'admin'::public.app_role);

  INSERT INTO public.seasons(id, league_id, season_number, status, started_at, name)
  VALUES (_season_id, _league_id, 9601, 'active', pg_catalog.now(), 'Match Simulation SQL');

  INSERT INTO public.season_participants(season_id, club_id, sort_order)
  SELECT _season_id, _clubs[i], i::smallint
  FROM generate_subscripts(_clubs, 1) AS selected(i);

  INSERT INTO public.rounds(id, season_id, round_number, lineup_lock_at, starts_at, ends_at)
  VALUES (
    _round_id,
    _season_id,
    1,
    pg_catalog.now() - interval '1 minute',
    pg_catalog.now(),
    pg_catalog.now() + interval '10 minutes'
  );

  INSERT INTO public.matches(id, round_id, home_club_id, away_club_id, status, scheduled_at)
  VALUES
    ('00000000-0000-0000-0000-000000061401'::uuid, _round_id, _clubs[1], _clubs[2], 'scheduled'::public.match_status, pg_catalog.now()),
    ('00000000-0000-0000-0000-000000061402'::uuid, _round_id, _clubs[3], _clubs[4], 'scheduled'::public.match_status, pg_catalog.now()),
    ('00000000-0000-0000-0000-000000061403'::uuid, _round_id, _clubs[5], _clubs[6], 'scheduled'::public.match_status, pg_catalog.now());
  _match_id := '00000000-0000-0000-0000-000000061401'::uuid;

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
        'BFMS-' || _i::text || '-' || _slot::text,
        'Match Sim Player ' || _i::text || '-' || _slot::text,
        (ARRAY['GK','DEF','DEF','MID','ATA'])[_slot]::public.player_position,
        'paia'::public.player_rarity,
        'centro'::public.player_sector,
        65 + _i,
        60 + _i,
        61 + _i,
        62 + _i,
        63 + _i,
        64 + _i,
        65 + _i,
        66 + _i,
        1000
      )
      RETURNING id INTO _player_id;

      SELECT id INTO _card_id
      FROM public.club_players
      WHERE player_id = _player_id
      FOR UPDATE;

      DELETE FROM public.system_market_stock WHERE club_player_id = _card_id;
      UPDATE public.club_players SET club_id = _clubs[_i], is_reserved = false WHERE id = _card_id;

      IF _i = 1 THEN
        _manual_cards := _manual_cards || _card_id;
      END IF;
    END LOOP;
  END LOOP;

  PERFORM pg_catalog.set_config('request.jwt.claim.sub', _regular_user::text, true);
  BEGIN
    PERFORM public.simulate_match(_match_id);
    RAISE EXCEPTION 'assertion_failed: regular user simulated a match';
  EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS _message = MESSAGE_TEXT;
    IF _message <> 'forbidden_not_admin' THEN
      RAISE EXCEPTION 'assertion_failed: expected forbidden_not_admin, got %', _message;
    END IF;
  END;

  PERFORM pg_catalog.set_config('request.jwt.claim.sub', _admin_user::text, true);

  _payload := pg_catalog.jsonb_build_array(
    pg_catalog.jsonb_build_object('club_player_id', _manual_cards[1], 'slot_position', 'GK', 'is_starter', true, 'slot_index', 1),
    pg_catalog.jsonb_build_object('club_player_id', _manual_cards[2], 'slot_position', 'DEF', 'is_starter', true, 'slot_index', 1),
    pg_catalog.jsonb_build_object('club_player_id', _manual_cards[3], 'slot_position', 'DEF', 'is_starter', true, 'slot_index', 2),
    pg_catalog.jsonb_build_object('club_player_id', _manual_cards[4], 'slot_position', 'MID', 'is_starter', true, 'slot_index', 1),
    pg_catalog.jsonb_build_object('club_player_id', _manual_cards[5], 'slot_position', 'ATA', 'is_starter', true, 'slot_index', 1)
  );

  PERFORM pg_catalog.set_config('request.jwt.claim.sub', _users[1]::text, true);
  UPDATE public.rounds SET lineup_lock_at = pg_catalog.now() + interval '1 hour' WHERE id = _round_id;
  PERFORM public.save_lineup(_round_id, '1-2-1-1'::public.formation, 'offensive'::public.play_style, _payload);
  UPDATE public.rounds SET lineup_lock_at = pg_catalog.now() - interval '1 minute' WHERE id = _round_id;

  PERFORM pg_catalog.set_config('request.jwt.claim.sub', _admin_user::text, true);
  SELECT public.simulate_match(_match_id) INTO _first;
  SELECT public.simulate_match(_match_id) INTO _second;

  IF _first <> _second THEN
    RAISE EXCEPTION 'assertion_failed: simulate_match not idempotent';
  END IF;

  IF (_first->>'status') <> 'finished' THEN
    RAISE EXCEPTION 'assertion_failed: match did not finish %', _first;
  END IF;

  SELECT count(*) INTO _event_count FROM public.match_events WHERE match_id = _match_id;
  SELECT count(*) INTO _snapshot_count FROM public.match_lineup_snapshots WHERE match_id = _match_id;
  SELECT count(*) INTO _reward_count
  FROM public.wallet_transactions
  WHERE reference_table = 'matches'
    AND reference_id = _match_id
    AND kind = 'match_reward'::public.wallet_transaction_type;

  IF _event_count < 5 THEN RAISE EXCEPTION 'assertion_failed: events not persisted'; END IF;
  IF _snapshot_count <> 10 THEN RAISE EXCEPTION 'assertion_failed: expected 10 lineup snapshots, got %', _snapshot_count; END IF;
  IF _reward_count <> 2 THEN RAISE EXCEPTION 'assertion_failed: expected one reward ledger per club, got %', _reward_count; END IF;

  IF NOT EXISTS (
    SELECT 1 FROM public.match_lineup_snapshots
    WHERE match_id = _match_id
      AND club_id = _clubs[1]
      AND lineup_origin = 'manual'
  ) THEN
    RAISE EXCEPTION 'assertion_failed: manual lineup snapshot missing';
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM public.match_lineup_snapshots
    WHERE match_id = _match_id
      AND club_id = _clubs[2]
      AND lineup_origin = 'automatic'
  ) THEN
    RAISE EXCEPTION 'assertion_failed: automatic lineup snapshot missing';
  END IF;

  IF (
    SELECT home_goals + away_goals FROM public.matches WHERE id = _match_id
  ) <> (
    SELECT count(*) FROM public.match_events WHERE match_id = _match_id AND event_type = 'goal'::public.match_event_type
  ) THEN
    RAISE EXCEPTION 'assertion_failed: score does not match goal events';
  END IF;

  IF EXISTS (
    SELECT 1
    FROM public.match_statistics
    WHERE match_id = _match_id
      AND (shots_on_target < goals OR chances < shots OR shots < shots_on_target)
  ) THEN
    RAISE EXCEPTION 'assertion_failed: inconsistent statistics';
  END IF;

  IF EXISTS (
    SELECT 1
    FROM public.match_events
    WHERE match_id = _match_id
      AND minute NOT BETWEEN 0 AND 90
  ) THEN
    RAISE EXCEPTION 'assertion_failed: event minute out of range';
  END IF;

  SELECT public.simulate_round(_round_id) INTO _round_result;
  IF (_round_result->>'simulated_count')::integer <> 2 THEN
    RAISE EXCEPTION 'assertion_failed: simulate_round should ignore one finished match, got %', _round_result;
  END IF;
  IF (SELECT count(*) FROM public.matches WHERE round_id = _round_id AND status = 'finished'::public.match_status) <> 3 THEN
    RAISE EXCEPTION 'assertion_failed: round did not finish all three matches';
  END IF;
  IF NOT (SELECT is_processed FROM public.rounds WHERE id = _round_id) THEN
    RAISE EXCEPTION 'assertion_failed: round not marked processed';
  END IF;

  INSERT INTO public.matches(id, round_id, home_club_id, away_club_id, status, scheduled_at)
  VALUES (_blocked_match_id, _round_id, _clubs[1], _clubs[2], 'scheduled'::public.match_status, pg_catalog.now());
  DELETE FROM public.club_players WHERE club_id = _clubs[2];
  BEGIN
    PERFORM public.simulate_match(_blocked_match_id);
    RAISE EXCEPTION 'assertion_failed: insufficient roster simulation succeeded';
  EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS _message = MESSAGE_TEXT;
    IF _message <> 'lineup_auto_insufficient_players' THEN
      RAISE EXCEPTION 'assertion_failed: expected lineup_auto_insufficient_players, got %', _message;
    END IF;
  END;
  IF EXISTS (SELECT 1 FROM public.match_events WHERE match_id = _blocked_match_id) THEN
    RAISE EXCEPTION 'assertion_failed: rollback left partial events';
  END IF;
  IF EXISTS (
    SELECT 1 FROM public.wallet_transactions
    WHERE reference_table = 'matches'
      AND reference_id = _blocked_match_id
  ) THEN
    RAISE EXCEPTION 'assertion_failed: rollback left partial reward';
  END IF;
END;
$$;

ROLLBACK;
