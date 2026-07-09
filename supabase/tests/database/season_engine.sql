-- Local database contract test for season setup, season_start, standings,
-- season_finish, and final prizes. It is transactional and rolls back fixtures.

BEGIN;

DO $$
DECLARE
  _league_id uuid;
  _badge_id uuid;
  _admin_user uuid := '00000000-0000-0000-0000-000000051001'::uuid;
  _users uuid[] := ARRAY[
    '00000000-0000-0000-0000-000000051001'::uuid,
    '00000000-0000-0000-0000-000000051002'::uuid,
    '00000000-0000-0000-0000-000000051003'::uuid,
    '00000000-0000-0000-0000-000000051004'::uuid,
    '00000000-0000-0000-0000-000000051005'::uuid,
    '00000000-0000-0000-0000-000000051006'::uuid,
    '00000000-0000-0000-0000-000000051007'::uuid,
    '00000000-0000-0000-0000-000000051008'::uuid,
    '00000000-0000-0000-0000-000000051009'::uuid
  ];
  _clubs uuid[] := ARRAY[
    '00000000-0000-0000-0000-000000051101'::uuid,
    '00000000-0000-0000-0000-000000051102'::uuid,
    '00000000-0000-0000-0000-000000051103'::uuid,
    '00000000-0000-0000-0000-000000051104'::uuid,
    '00000000-0000-0000-0000-000000051105'::uuid,
    '00000000-0000-0000-0000-000000051106'::uuid,
    '00000000-0000-0000-0000-000000051107'::uuid,
    '00000000-0000-0000-0000-000000051108'::uuid,
    '00000000-0000-0000-0000-000000051109'::uuid
  ];
  _config_id uuid;
  _season_id uuid;
  _match_id uuid;
  _champion uuid;
  _message text;
  _state jsonb;
  _result jsonb;
  _row_count integer;
  _i integer;
BEGIN
  SELECT id INTO _league_id FROM public.leagues WHERE slug = 'bagreleirao';
  IF _league_id IS NULL THEN RAISE EXCEPTION 'test_setup_failed: league_missing'; END IF;

  SELECT id INTO _badge_id
  FROM public.club_badges
  WHERE is_active
  ORDER BY sort_order, code
  LIMIT 1;
  IF _badge_id IS NULL THEN RAISE EXCEPTION 'test_setup_failed: badge_missing'; END IF;

  UPDATE public.leagues SET status = 'setup', max_clubs = 1000 WHERE id = _league_id;

  DELETE FROM public.wallet_transactions WHERE club_id = ANY(_clubs);
  DELETE FROM public.match_events WHERE match_id IN (
    SELECT m.id
    FROM public.matches m
    JOIN public.rounds r ON r.id = m.round_id
    JOIN public.seasons s ON s.id = r.season_id
    WHERE s.league_id = _league_id
      AND s.season_number >= 900
  );
  DELETE FROM public.season_configurations WHERE name = 'Temporada SQL';
  DELETE FROM public.seasons WHERE league_id = _league_id AND name = 'Temporada SQL';
  DELETE FROM public.clubs WHERE id = ANY(_clubs) OR owner_id = ANY(_users);
  DELETE FROM public.user_roles WHERE user_id = ANY(_users);
  DELETE FROM public.profiles WHERE id = ANY(_users);
  DELETE FROM auth.users WHERE id = ANY(_users);

  FOR _i IN 1..pg_catalog.array_length(_users, 1) LOOP
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
      'season-' || _i::text || '@example.test',
      'test-password',
      pg_catalog.now(),
      '{"provider":"email","providers":["email"]}'::jsonb,
      pg_catalog.jsonb_build_object('username', 'seas' || pg_catalog.lpad(_i::text, 2, '0')),
      pg_catalog.now(),
      pg_catalog.now()
    );
  END LOOP;

  UPDATE public.profiles SET status = 'approved'::public.user_status WHERE id = ANY(_users[1:7]);
  UPDATE public.profiles SET status = 'pending'::public.user_status WHERE id = _users[8];
  UPDATE public.profiles SET status = 'blocked'::public.user_status WHERE id = _users[9];

  INSERT INTO public.user_roles (user_id, role)
  VALUES (_admin_user, 'admin'::public.app_role);

  FOR _i IN 1..9 LOOP
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
      'Season Club ' || _i::text,
      public.normalize_club_name('Season Club ' || _i::text),
      'S' || pg_catalog.lpad(_i::text, 2, '0'),
      _badge_id,
      0,
      true
    );
  END LOOP;

  PERFORM pg_catalog.set_config('request.jwt.claim.sub', _admin_user::text, true);

  SELECT public.get_season_operational_state() INTO _state;
  IF _state->>'operational_status' <> 'ready_to_start' THEN
    RAISE EXCEPTION 'assertion_failed: expected ready_to_start with seven eligible clubs, got %', _state;
  END IF;
  IF (_state->>'eligible_count')::integer <> 7 THEN
    RAISE EXCEPTION 'assertion_failed: expected seven eligible clubs';
  END IF;

  SELECT (public.admin_upsert_season_setup(
    jsonb_build_object(
      'name', 'Temporada SQL',
      'start_date', '2026-08-01',
      'default_match_time', '22:00',
      'round_interval_days', 1,
      'timezone', 'America/Belem',
      'registration_status', 'closed',
      'registration_deadline', '2026-07-31',
      'prizes_cents', jsonb_build_array(600, 500, 400, 300, 200, 100)
    )
  )->>'config_id')::uuid
  INTO _config_id;

  PERFORM public.admin_set_season_participants(_config_id, _clubs[1:5]);
  BEGIN
    PERFORM public.season_start(_config_id);
    RAISE EXCEPTION 'assertion_failed: season_start accepted fewer than six clubs';
  EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS _message = MESSAGE_TEXT;
    IF _message <> 'season_selection_requires_exactly_6' THEN
      RAISE EXCEPTION 'assertion_failed: expected season_selection_requires_exactly_6, got %', _message;
    END IF;
  END;

  IF EXISTS (
    SELECT 1
    FROM public.seasons s
    WHERE s.league_id = _league_id
      AND s.status = 'active'
  ) THEN
    RAISE EXCEPTION 'assertion_failed: partial season was created after invalid start';
  END IF;

  PERFORM public.admin_set_season_participants(_config_id, ARRAY[_clubs[1], _clubs[2], _clubs[3], _clubs[4], _clubs[5], _clubs[9]]);
  BEGIN
    PERFORM public.season_start(_config_id);
    RAISE EXCEPTION 'assertion_failed: season_start accepted blocked club';
  EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS _message = MESSAGE_TEXT;
    IF _message <> 'season_selected_club_ineligible' THEN
      RAISE EXCEPTION 'assertion_failed: expected season_selected_club_ineligible, got %', _message;
    END IF;
  END;

  PERFORM public.admin_set_season_participants(_config_id, _clubs[1:6]);
  SELECT public.season_start(_config_id) INTO _result;
  _season_id := (_result->>'season_id')::uuid;

  IF (_result->>'round_count')::integer <> 10 OR (_result->>'match_count')::integer <> 30 THEN
    RAISE EXCEPTION 'assertion_failed: wrong generated counts %', _result;
  END IF;

  IF (SELECT pg_catalog.count(*) FROM public.rounds WHERE season_id = _season_id) <> 10 THEN
    RAISE EXCEPTION 'assertion_failed: expected 10 rounds';
  END IF;
  IF (
    SELECT pg_catalog.count(*)
    FROM public.matches m
    JOIN public.rounds r ON r.id = m.round_id
    WHERE r.season_id = _season_id
  ) <> 30 THEN
    RAISE EXCEPTION 'assertion_failed: expected 30 matches';
  END IF;
  IF EXISTS (
    SELECT r.round_number
    FROM public.rounds r
    JOIN public.matches m ON m.round_id = r.id
    WHERE r.season_id = _season_id
    GROUP BY r.round_number
    HAVING pg_catalog.count(*) <> 3
  ) THEN
    RAISE EXCEPTION 'assertion_failed: every round must have three matches';
  END IF;
  IF EXISTS (
    SELECT club_id
    FROM (
      SELECT m.home_club_id AS club_id
      FROM public.matches m
      JOIN public.rounds r ON r.id = m.round_id
      WHERE r.season_id = _season_id
      UNION ALL
      SELECT m.away_club_id
      FROM public.matches m
      JOIN public.rounds r ON r.id = m.round_id
      WHERE r.season_id = _season_id
    ) club_matches
    GROUP BY club_id
    HAVING pg_catalog.count(*) <> 10
  ) THEN
    RAISE EXCEPTION 'assertion_failed: each club must play ten matches';
  END IF;
  IF EXISTS (
    SELECT least(home_club_id, away_club_id), greatest(home_club_id, away_club_id)
    FROM public.matches m
    JOIN public.rounds r ON r.id = m.round_id
    WHERE r.season_id = _season_id
    GROUP BY least(home_club_id, away_club_id), greatest(home_club_id, away_club_id)
    HAVING pg_catalog.count(*) <> 2
       OR pg_catalog.count(*) FILTER (WHERE home_club_id < away_club_id) NOT IN (0, 1, 2)
  ) THEN
    RAISE EXCEPTION 'assertion_failed: every pair must play twice';
  END IF;
  IF EXISTS (
    SELECT 1
    FROM public.matches m1
    JOIN public.rounds r1 ON r1.id = m1.round_id
    JOIN public.matches m2
      ON m2.id <> m1.id
     AND least(m2.home_club_id, m2.away_club_id) = least(m1.home_club_id, m1.away_club_id)
     AND greatest(m2.home_club_id, m2.away_club_id) = greatest(m1.home_club_id, m1.away_club_id)
    JOIN public.rounds r2 ON r2.id = m2.round_id
    WHERE r1.season_id = _season_id
      AND r2.season_id = _season_id
      AND m1.home_club_id = m2.home_club_id
  ) THEN
    RAISE EXCEPTION 'assertion_failed: return match did not invert home/away';
  END IF;

  SELECT public.season_start(_config_id) INTO _result;
  IF (_result->>'season_id')::uuid <> _season_id THEN
    RAISE EXCEPTION 'assertion_failed: season_start is not idempotent';
  END IF;

  IF (SELECT pg_catalog.count(*) FROM public.get_season_standings(_season_id)) <> 6 THEN
    RAISE EXCEPTION 'assertion_failed: standings must return six clubs';
  END IF;

  SELECT m.id INTO _match_id
  FROM public.matches m
  JOIN public.rounds r ON r.id = m.round_id
  WHERE r.season_id = _season_id
  ORDER BY r.round_number, m.created_at
  LIMIT 1;

  UPDATE public.matches
  SET home_goals = 2,
      away_goals = 1,
      status = 'finished'::public.match_status,
      simulated_at = pg_catalog.now()
  WHERE id = _match_id;

  IF NOT EXISTS (
    SELECT 1
    FROM public.get_season_standings(_season_id) s
    JOIN public.matches m ON m.id = _match_id
    WHERE s.club_id = m.home_club_id
      AND s.points = 3
      AND s.wins = 1
      AND s.goal_difference = 1
  ) THEN
    RAISE EXCEPTION 'assertion_failed: win did not add three points';
  END IF;

  BEGIN
    PERFORM public.season_finish(_season_id);
    RAISE EXCEPTION 'assertion_failed: season finished with pending matches';
  EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS _message = MESSAGE_TEXT;
    IF _message <> 'season_has_pending_matches' THEN
      RAISE EXCEPTION 'assertion_failed: expected season_has_pending_matches, got %', _message;
    END IF;
  END;

  UPDATE public.matches m
  SET home_goals = CASE WHEN m.home_club_id = _clubs[1] THEN 3 WHEN m.away_club_id = _clubs[1] THEN 0 ELSE 1 END,
      away_goals = CASE WHEN m.away_club_id = _clubs[1] THEN 3 WHEN m.home_club_id = _clubs[1] THEN 0 ELSE 1 END,
      status = 'finished'::public.match_status,
      simulated_at = pg_catalog.now()
  FROM public.rounds r
  WHERE r.id = m.round_id
    AND r.season_id = _season_id;

  SELECT club_id INTO _champion
  FROM public.get_season_standings(_season_id) s
  ORDER BY s."position"
  LIMIT 1;
  IF _champion <> _clubs[1] THEN
    RAISE EXCEPTION 'assertion_failed: champion should be first selected club';
  END IF;

  SELECT public.season_finish(_season_id) INTO _result;
  IF (_result->>'champion_club_id')::uuid <> _clubs[1] THEN
    RAISE EXCEPTION 'assertion_failed: finish returned wrong champion';
  END IF;

  SELECT pg_catalog.count(*) INTO _row_count
  FROM public.wallet_transactions
  WHERE reference_table = 'seasons'
    AND reference_id = _season_id
    AND kind = 'season_prize'::public.wallet_transaction_type;
  IF _row_count <> 6 THEN
    RAISE EXCEPTION 'assertion_failed: expected one season_prize ledger row per club';
  END IF;

  BEGIN
    PERFORM public.season_finish(_season_id);
    RAISE EXCEPTION 'assertion_failed: duplicate season finish succeeded';
  EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS _message = MESSAGE_TEXT;
    IF _message <> 'season_not_active' THEN
      RAISE EXCEPTION 'assertion_failed: expected season_not_active, got %', _message;
    END IF;
  END;

  RAISE NOTICE 'season_engine contract test passed';
END $$;

ROLLBACK;
