-- Local database contract test for public.open_initial_pack(uuid).
-- Intended for a local Supabase/Postgres database. The script is transactional
-- and rolls back all fixture data at the end.

BEGIN;

DO $$
DECLARE
  _league_id uuid;
  _badge_id uuid;
  _user_ids uuid[] := ARRAY[]::uuid[];
  _club_ids uuid[] := ARRAY[]::uuid[];
  _foreign_club_id uuid;
  _pending_club_id uuid;
  _sink_club_id uuid;
  _shortage_club_id uuid;
  _pack_id uuid;
  _count integer;
  _duplicates integer;
  _i integer;
  _code text;
  _message text;
BEGIN
  SELECT l.id INTO _league_id
  FROM public.leagues l
  WHERE l.slug = 'bagreleirao';

  IF _league_id IS NULL THEN
    RAISE EXCEPTION 'test_setup_failed: bagreleirao league not found';
  END IF;

  UPDATE public.leagues
  SET status = 'setup'
  WHERE id = _league_id;

  SELECT b.id INTO _badge_id
  FROM public.club_badges b
  WHERE b.is_active
  ORDER BY b.sort_order, b.code
  LIMIT 1;

  IF _badge_id IS NULL THEN
    RAISE EXCEPTION 'test_setup_failed: active badge not found';
  END IF;

  FOR _i IN 1..10 LOOP
    _user_ids := _user_ids || (('00000000-0000-0000-0000-' || pg_catalog.lpad((100 + _i)::text, 12, '0'))::uuid);
    _club_ids := _club_ids || (('00000000-0000-0000-0000-' || pg_catalog.lpad((200 + _i)::text, 12, '0'))::uuid);
  END LOOP;

  _foreign_club_id := _club_ids[7];
  _pending_club_id := _club_ids[8];
  _sink_club_id := _club_ids[9];
  _shortage_club_id := _club_ids[10];

  DELETE FROM public.initial_pack_items ipi
  USING public.initial_packs ip
  WHERE ipi.pack_id = ip.id
    AND ip.club_id = ANY(_club_ids);

  DELETE FROM public.club_players cp
  WHERE cp.club_id = ANY(_club_ids)
     OR cp.player_id IN (SELECT p.id FROM public.players p WHERE p.code LIKE 'BFTST-%');

  DELETE FROM public.initial_packs ip
  WHERE ip.club_id = ANY(_club_ids);

  DELETE FROM public.clubs c
  WHERE c.id = ANY(_club_ids)
     OR c.owner_id = ANY(_user_ids);

  DELETE FROM public.players p
  WHERE p.code LIKE 'BFTST-%';

  DELETE FROM public.profiles p
  WHERE p.id = ANY(_user_ids);

  DELETE FROM auth.users u
  WHERE u.id = ANY(_user_ids);

  FOR _i IN 1..10 LOOP
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
      _user_ids[_i],
      '00000000-0000-0000-0000-000000000000',
      'authenticated',
      'authenticated',
      'bagrefut-test-' || _i::text || '@example.test',
      'test-password',
      pg_catalog.now(),
      '{"provider":"email","providers":["email"]}'::jsonb,
      pg_catalog.jsonb_build_object('username', 'bftest' || pg_catalog.lpad(_i::text, 2, '0')),
      pg_catalog.now(),
      pg_catalog.now()
    );

    UPDATE public.profiles
    SET status = CASE WHEN _i = 8 THEN 'pending'::public.user_status ELSE 'approved'::public.user_status END
    WHERE id = _user_ids[_i];

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
    VALUES (
      _club_ids[_i],
      _league_id,
      _user_ids[_i],
      'Bagre Teste ' || _i::text,
      public.normalize_club_name('Bagre Teste ' || _i::text),
      (ARRAY['BAA','BBB','BCC','BDD','BEE','BFF','BGG','BHH','BII','BJJ'])[_i],
      _badge_id,
      0
    );

    INSERT INTO public.initial_packs (club_id)
    VALUES (_club_ids[_i]);
  END LOOP;

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
  SELECT
    'BFTST-' || pg_catalog.lpad(g.i::text, 3, '0'),
    'Bagre Teste ' || g.i::text,
    (ARRAY['GK','DEF','MID','ATA'])[((g.i - 1) % 4) + 1]::public.player_position,
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
  FROM pg_catalog.generate_series(1, 69) AS g(i);

  -- User cannot open another user's unopened pack.
  PERFORM pg_catalog.set_config('request.jwt.claim.sub', _user_ids[1]::text, true);
  BEGIN
    PERFORM * FROM public.open_initial_pack(_foreign_club_id);
    RAISE EXCEPTION 'assertion_failed: user opened another club pack';
  EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS _message = MESSAGE_TEXT;
    IF _message <> 'not_club_owner' THEN
      RAISE EXCEPTION 'assertion_failed: expected not_club_owner, got %', _message;
    END IF;
  END;

  -- Pending user cannot open their own pack.
  PERFORM pg_catalog.set_config('request.jwt.claim.sub', _user_ids[8]::text, true);
  BEGIN
    PERFORM * FROM public.open_initial_pack(_pending_club_id);
    RAISE EXCEPTION 'assertion_failed: pending user opened pack';
  EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS _message = MESSAGE_TEXT;
    IF _message <> 'profile_not_approved' THEN
      RAISE EXCEPTION 'assertion_failed: expected profile_not_approved, got %', _message;
    END IF;
  END;

  -- First pack opens once and returns exactly 10 rows.
  PERFORM pg_catalog.set_config('request.jwt.claim.sub', _user_ids[1]::text, true);
  SELECT pg_catalog.count(*) INTO _count
  FROM public.open_initial_pack(_club_ids[1]);

  IF _count <> 10 THEN
    RAISE EXCEPTION 'assertion_failed: expected 10 rows from first open, got %', _count;
  END IF;

  SELECT pg_catalog.count(*) INTO _count
  FROM public.club_players cp
  WHERE cp.club_id = _club_ids[1];

  IF _count <> 10 THEN
    RAISE EXCEPTION 'assertion_failed: expected 10 club_players for first club, got %', _count;
  END IF;

  BEGIN
    PERFORM * FROM public.open_initial_pack(_club_ids[1]);
    RAISE EXCEPTION 'assertion_failed: second open succeeded';
  EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS _message = MESSAGE_TEXT;
    IF _message <> 'pack_already_opened' THEN
      RAISE EXCEPTION 'assertion_failed: expected pack_already_opened, got %', _message;
    END IF;
  END;

  -- Open five more clubs. After six packs, exactly 60 players are distributed.
  FOR _i IN 2..6 LOOP
    PERFORM pg_catalog.set_config('request.jwt.claim.sub', _user_ids[_i]::text, true);
    SELECT pg_catalog.count(*) INTO _count
    FROM public.open_initial_pack(_club_ids[_i]);

    IF _count <> 10 THEN
      RAISE EXCEPTION 'assertion_failed: expected 10 rows from open %, got %', _i, _count;
    END IF;
  END LOOP;

  SELECT pg_catalog.count(*) INTO _count
  FROM public.club_players cp
  WHERE cp.club_id = ANY(_club_ids[1:6]);

  IF _count <> 60 THEN
    RAISE EXCEPTION 'assertion_failed: expected 60 distributed players after six packs, got %', _count;
  END IF;

  SELECT pg_catalog.count(*) INTO _duplicates
  FROM (
    SELECT cp.player_id
    FROM public.club_players cp
    WHERE cp.club_id = ANY(_club_ids[1:6])
    GROUP BY cp.player_id
    HAVING pg_catalog.count(*) > 1
  ) duplicated_players;

  IF _duplicates <> 0 THEN
    RAISE EXCEPTION 'assertion_failed: duplicate player distribution found';
  END IF;

  SELECT pg_catalog.count(*) INTO _count
  FROM public.club_players a
  JOIN public.club_players b ON b.player_id = a.player_id
  WHERE a.club_id = _club_ids[1]
    AND b.club_id = _club_ids[2];

  IF _count <> 0 THEN
    RAISE EXCEPTION 'assertion_failed: two clubs share players';
  END IF;

  -- Leave only nine unowned players, then verify the next open rolls back fully.
  INSERT INTO public.club_players (club_id, player_id)
  SELECT _sink_club_id, available.id
  FROM (
    SELECT p.id
    FROM public.players p
    WHERE NOT EXISTS (
      SELECT 1
      FROM public.club_players cp
      WHERE cp.player_id = p.id
    )
    ORDER BY p.id
    OFFSET 9
  ) AS available;

  PERFORM pg_catalog.set_config('request.jwt.claim.sub', _user_ids[10]::text, true);
  BEGIN
    PERFORM * FROM public.open_initial_pack(_shortage_club_id);
    RAISE EXCEPTION 'assertion_failed: shortage open succeeded';
  EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS _message = MESSAGE_TEXT;
    IF _message <> 'not_enough_players_available' THEN
      RAISE EXCEPTION 'assertion_failed: expected not_enough_players_available, got %', _message;
    END IF;
  END;

  SELECT ip.id INTO _pack_id
  FROM public.initial_packs ip
  WHERE ip.club_id = _shortage_club_id;

  SELECT pg_catalog.count(*) INTO _count
  FROM public.club_players cp
  WHERE cp.club_id = _shortage_club_id;

  IF _count <> 0 THEN
    RAISE EXCEPTION 'assertion_failed: shortage rollback left % club_players', _count;
  END IF;

  SELECT pg_catalog.count(*) INTO _count
  FROM public.initial_pack_items ipi
  WHERE ipi.pack_id = _pack_id;

  IF _count <> 0 THEN
    RAISE EXCEPTION 'assertion_failed: shortage rollback left % pack items', _count;
  END IF;

  SELECT pg_catalog.count(*) INTO _count
  FROM public.initial_packs ip
  WHERE ip.id = _pack_id
    AND ip.opened_at IS NOT NULL;

  IF _count <> 0 THEN
    RAISE EXCEPTION 'assertion_failed: shortage rollback marked pack opened';
  END IF;

  RAISE NOTICE 'open_initial_pack_concurrency contract test passed';
END $$;

ROLLBACK;

-- Manual concurrency test for two SQL sessions after applying the migration:
--
-- Session A:
-- BEGIN;
-- SELECT * FROM public.open_initial_pack('CLUB_ID_A');
--
-- Session B, before committing session A:
-- BEGIN;
-- SELECT * FROM public.open_initial_pack('CLUB_ID_B');
--
-- Then commit both sessions and validate:
-- SELECT player_id, COUNT(*)
-- FROM public.club_players
-- GROUP BY player_id
-- HAVING COUNT(*) > 1;
--
-- Expected result: 0 rows.
