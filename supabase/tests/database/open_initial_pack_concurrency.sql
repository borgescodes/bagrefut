-- Transactional contract test for public.open_initial_pack(uuid).
-- Apply 20260713160000_fair_starter_packs.sql before running.
-- Expected final NOTICE:
--   open_initial_pack_concurrency contract test passed

BEGIN;

DO $$
DECLARE
  _league_id uuid;
  _badge_id uuid;
  _user_ids uuid[] := ARRAY[]::uuid[];
  _club_ids uuid[] := ARRAY[]::uuid[];
  _template_ids uuid[] := ARRAY[]::uuid[];
  _foreign_club_id uuid;
  _pending_club_id uuid;
  _shortage_club_id uuid;
  _pack_id uuid;
  _count integer;
  _duplicates integer;
  _i integer;
  _message text;
BEGIN
  SELECT l.id INTO _league_id
  FROM public.leagues l
  WHERE l.slug = 'bagreleirao';

  SELECT b.id INTO _badge_id
  FROM public.club_badges b
  WHERE b.is_active
  ORDER BY b.sort_order, b.code
  LIMIT 1;

  IF _league_id IS NULL OR _badge_id IS NULL THEN
    RAISE EXCEPTION 'test_setup_failed: league or badge missing';
  END IF;

  UPDATE public.leagues
  SET status = 'setup',
      max_clubs = 1000
  WHERE id = _league_id;

  FOR _i IN 1..10 LOOP
    _user_ids := _user_ids || (
      ('00000000-0000-0000-0000-' || pg_catalog.lpad((100 + _i)::text, 12, '0'))::uuid
    );
    _club_ids := _club_ids || (
      ('00000000-0000-0000-0000-' || pg_catalog.lpad((200 + _i)::text, 12, '0'))::uuid
    );
  END LOOP;

  _foreign_club_id := _club_ids[7];
  _pending_club_id := _club_ids[8];
  _shortage_club_id := _club_ids[10];

  INSERT INTO public.players(
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
    CASE ((g.i - 1) % 10) + 1
      WHEN 1 THEN 'GK'::public.player_position
      WHEN 2 THEN 'GK'::public.player_position
      WHEN 3 THEN 'DEF'::public.player_position
      WHEN 4 THEN 'DEF'::public.player_position
      WHEN 5 THEN 'DEF'::public.player_position
      WHEN 6 THEN 'MID'::public.player_position
      WHEN 7 THEN 'MID'::public.player_position
      WHEN 8 THEN 'MID'::public.player_position
      ELSE 'ATA'::public.player_position
    END,
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
  FROM pg_catalog.generate_series(1, 100) AS g(i);

  FOR _i IN 1..10 LOOP
    INSERT INTO public.starter_pack_templates(
      code,
      expected_total_overall,
      expected_starter_overall
    )
    VALUES (
      'TEST_CONCURRENCY_' || pg_catalog.lpad(_i::text, 2, '0'),
      500,
      0
    )
    RETURNING id INTO _pack_id;

    _template_ids := _template_ids || _pack_id;

    INSERT INTO public.starter_pack_template_items(template_id, player_id, slot)
    SELECT
      _pack_id,
      p.id,
      pg_catalog.row_number() OVER (ORDER BY p.code)::smallint
    FROM public.players p
    WHERE p.code BETWEEN
      'BFTST-' || pg_catalog.lpad(((_i - 1) * 10 + 1)::text, 3, '0')
      AND 'BFTST-' || pg_catalog.lpad((_i * 10)::text, 3, '0');
  END LOOP;

  FOR _i IN 1..10 LOOP
    INSERT INTO auth.users(
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
    SET status = CASE
      WHEN _i = 8 THEN 'pending'::public.user_status
      ELSE 'approved'::public.user_status
    END
    WHERE id = _user_ids[_i];

    INSERT INTO public.clubs(
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

    INSERT INTO public.initial_packs(club_id, starter_pack_template_id)
    VALUES (_club_ids[_i], _template_ids[_i]);
  END LOOP;

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

  -- Pending user cannot open own pack.
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

  -- First open transfers exactly ten cards.
  PERFORM pg_catalog.set_config('request.jwt.claim.sub', _user_ids[1]::text, true);
  SELECT pg_catalog.count(*) INTO _count
  FROM public.open_initial_pack(_club_ids[1]);

  IF _count <> 10 THEN
    RAISE EXCEPTION 'assertion_failed: expected 10 rows from first open, got %', _count;
  END IF;

  IF (
    SELECT pg_catalog.count(*)
    FROM public.club_players cp
    WHERE cp.club_id = _club_ids[1]
  ) <> 10 THEN
    RAISE EXCEPTION 'assertion_failed: expected ten owned cards after first open';
  END IF;

  -- Reopening is idempotent and returns same ten rows.
  SELECT pg_catalog.count(*) INTO _count
  FROM public.open_initial_pack(_club_ids[1]);

  IF _count <> 10 THEN
    RAISE EXCEPTION 'assertion_failed: repeated open did not return ten rows';
  END IF;

  SELECT ip.id INTO _pack_id
  FROM public.initial_packs ip
  WHERE ip.club_id = _club_ids[1];

  IF (
    SELECT pg_catalog.count(*)
    FROM public.initial_pack_items ipi
    WHERE ipi.pack_id = _pack_id
  ) <> 10 THEN
    RAISE EXCEPTION 'assertion_failed: repeated open duplicated or removed items';
  END IF;

  -- Six clubs receive six disjoint predefined templates.
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
    RAISE EXCEPTION 'assertion_failed: expected 60 distributed players, got %', _count;
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

  IF (
    SELECT pg_catalog.count(DISTINCT ip.starter_pack_template_id)
    FROM public.initial_packs ip
    WHERE ip.club_id = ANY(_club_ids[1:6])
  ) <> 6 THEN
    RAISE EXCEPTION 'assertion_failed: template repeated between clubs';
  END IF;

  -- Making one assigned card commercial blocks opening and rolls back fully.
  UPDATE public.system_market_stock sms
  SET is_market_eligible = true
  WHERE sms.club_player_id = (
    SELECT cp.id
    FROM public.club_players cp
    JOIN public.starter_pack_template_items i ON i.player_id = cp.player_id
    WHERE i.template_id = _template_ids[10]
    ORDER BY i.slot
    LIMIT 1
  );

  PERFORM pg_catalog.set_config('request.jwt.claim.sub', _user_ids[10]::text, true);
  BEGIN
    PERFORM * FROM public.open_initial_pack(_shortage_club_id);
    RAISE EXCEPTION 'assertion_failed: unavailable-card open succeeded';
  EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS _message = MESSAGE_TEXT;
    IF _message <> 'starter_pack_card_unavailable' THEN
      RAISE EXCEPTION 'assertion_failed: expected starter_pack_card_unavailable, got %', _message;
    END IF;
  END;

  SELECT ip.id INTO _pack_id
  FROM public.initial_packs ip
  WHERE ip.club_id = _shortage_club_id;

  IF EXISTS (
    SELECT 1
    FROM public.club_players cp
    WHERE cp.club_id = _shortage_club_id
  ) OR EXISTS (
    SELECT 1
    FROM public.initial_pack_items ipi
    WHERE ipi.pack_id = _pack_id
  ) OR EXISTS (
    SELECT 1
    FROM public.initial_packs ip
    WHERE ip.id = _pack_id
      AND ip.opened_at IS NOT NULL
  ) THEN
    RAISE EXCEPTION 'assertion_failed: failed open was not atomic';
  END IF;

  RAISE NOTICE 'open_initial_pack_concurrency contract test passed';
END;
$$;

ROLLBACK;

-- Manual concurrency test after applying migration:
--
-- Session A:
-- BEGIN;
-- SELECT * FROM public.create_club('Concurrent A', 'CNA', 'BADGE_CODE');
--
-- Session B, before committing session A:
-- BEGIN;
-- SELECT * FROM public.create_club('Concurrent B', 'CNB', 'BADGE_CODE');
--
-- Commit both and validate no repeated template:
-- SELECT starter_pack_template_id, COUNT(*)
-- FROM public.initial_packs
-- GROUP BY starter_pack_template_id
-- HAVING COUNT(*) > 1;
--
-- Expected result: 0 rows.
