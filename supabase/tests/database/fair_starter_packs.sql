-- Transactional contract test for fair starter-pack templates and opening.
-- Apply 20260713160000_fair_starter_packs.sql before running.
-- Expected final NOTICE:
--   fair_starter_packs contract test passed
--
-- Safe behavior: all fixture data is rolled back.

BEGIN;

DO $$
DECLARE
  _expected jsonb := pg_catalog.jsonb_build_object(
    'PACK01', pg_catalog.jsonb_build_array('GK05','GK11','DEF11','DEF09','DEF03','MID04','MID14','MID13','ATA01','ATA12'),
    'PACK02', pg_catalog.jsonb_build_array('GK01','GK03','DEF05','DEF02','DEF16','MID08','MID09','MID18','ATA07','ATA08'),
    'PACK03', pg_catalog.jsonb_build_array('GK02','GK12','DEF10','DEF14','DEF13','MID05','MID06','MID15','ATA04','ATA03'),
    'PACK04', pg_catalog.jsonb_build_array('GK06','GK09','DEF07','DEF08','DEF18','MID07','MID02','MID12','ATA06','ATA09'),
    'PACK05', pg_catalog.jsonb_build_array('GK07','GK10','DEF01','DEF17','DEF12','MID10','MID03','MID17','ATA02','ATA11'),
    'PACK06', pg_catalog.jsonb_build_array('GK04','GK08','DEF04','DEF06','DEF15','MID01','MID11','MID16','ATA05','ATA10')
  );
  _fixture_user uuid := '00000000-0000-0000-0000-000000071301'::uuid;
  _fixture_club uuid := '00000000-0000-0000-0000-000000071302'::uuid;
  _fixture_pack uuid := '00000000-0000-0000-0000-000000071303'::uuid;
  _fixture_template uuid;
  _league_id uuid;
  _badge_id uuid;
  _blocked_card uuid;
  _code text;
  _actual jsonb;
  _opened_codes text[];
  _opened_again text[];
  _count integer;
  _message text;
BEGIN
  IF (
    SELECT pg_catalog.count(*)
    FROM public.starter_pack_templates t
    WHERE t.code ~ '^PACK0[1-6]$'
  ) <> 6 THEN
    RAISE EXCEPTION 'assertion_failed: expected six production templates';
  END IF;

  IF (
    SELECT pg_catalog.count(*)
    FROM public.starter_pack_template_items i
    JOIN public.starter_pack_templates t ON t.id = i.template_id
    WHERE t.code ~ '^PACK0[1-6]$'
  ) <> 60 THEN
    RAISE EXCEPTION 'assertion_failed: expected sixty production template items';
  END IF;

  IF (
    SELECT pg_catalog.count(DISTINCT i.player_id)
    FROM public.starter_pack_template_items i
    JOIN public.starter_pack_templates t ON t.id = i.template_id
    WHERE t.code ~ '^PACK0[1-6]$'
  ) <> 60 THEN
    RAISE EXCEPTION 'assertion_failed: production player repeated between templates';
  END IF;

  FOR _code IN SELECT pg_catalog.jsonb_object_keys(_expected) LOOP
    SELECT pg_catalog.jsonb_agg(p.code ORDER BY i.slot)
    INTO _actual
    FROM public.starter_pack_templates t
    JOIN public.starter_pack_template_items i ON i.template_id = t.id
    JOIN public.players p ON p.id = i.player_id
    WHERE t.code = _code;

    IF _actual <> _expected -> _code THEN
      RAISE EXCEPTION 'assertion_failed: composition mismatch for %, got %', _code, _actual;
    END IF;
  END LOOP;

  IF EXISTS (
    SELECT 1
    FROM public.starter_pack_templates t
    JOIN public.starter_pack_template_items i ON i.template_id = t.id
    JOIN public.players p ON p.id = i.player_id
    WHERE t.code ~ '^PACK0[1-6]$'
    GROUP BY t.id
    HAVING pg_catalog.count(*) <> 10
       OR pg_catalog.count(*) FILTER (WHERE p.position = 'GK') <> 2
       OR pg_catalog.count(*) FILTER (WHERE p.position = 'DEF') <> 3
       OR pg_catalog.count(*) FILTER (WHERE p.position = 'MID') <> 3
       OR pg_catalog.count(*) FILTER (WHERE p.position = 'ATA') <> 2
       OR pg_catalog.sum(p.overall) <> t.expected_total_overall
  ) THEN
    RAISE EXCEPTION 'assertion_failed: package shape or OVR mismatch';
  END IF;

  IF EXISTS (
    SELECT ip.starter_pack_template_id
    FROM public.initial_packs ip
    GROUP BY ip.starter_pack_template_id
    HAVING pg_catalog.count(*) > 1
  ) THEN
    RAISE EXCEPTION 'assertion_failed: template assigned more than once';
  END IF;

  SELECT l.id
  INTO _league_id
  FROM public.leagues l
  WHERE l.slug = 'bagreleirao';

  SELECT b.id
  INTO _badge_id
  FROM public.club_badges b
  WHERE b.is_active
  ORDER BY b.sort_order, b.code
  LIMIT 1;

  IF _league_id IS NULL OR _badge_id IS NULL THEN
    RAISE EXCEPTION 'test_setup_failed: league or badge missing';
  END IF;

  UPDATE public.leagues
  SET status = 'setup'
  WHERE id = _league_id;

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
    _fixture_user,
    '00000000-0000-0000-0000-000000000000',
    'authenticated',
    'authenticated',
    'fair-pack-fixture@example.test',
    'test-password',
    pg_catalog.now(),
    '{"provider":"email","providers":["email"]}'::jsonb,
    '{"username":"fairpackfixture"}'::jsonb,
    pg_catalog.now(),
    pg_catalog.now()
  );

  UPDATE public.profiles
  SET status = 'approved'
  WHERE id = _fixture_user;

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
    _fixture_club,
    _league_id,
    _fixture_user,
    'Fair Pack Fixture',
    public.normalize_club_name('Fair Pack Fixture'),
    'FPF',
    _badge_id,
    1000
  );

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
    'FSPK' || pg_catalog.lpad(g.i::text, 2, '0'),
    'Fair Starter Fixture ' || g.i::text,
    CASE
      WHEN g.i <= 2 THEN 'GK'::public.player_position
      WHEN g.i <= 5 THEN 'DEF'::public.player_position
      WHEN g.i <= 8 THEN 'MID'::public.player_position
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
  FROM pg_catalog.generate_series(1, 10) AS g(i);

  INSERT INTO public.starter_pack_templates(
    code,
    expected_total_overall,
    expected_starter_overall
  )
  SELECT
    'TEST_FAIR_PACK',
    pg_catalog.sum(p.overall)::smallint,
    0
  FROM public.players p
  WHERE p.code LIKE 'FSPK%'
  RETURNING id INTO _fixture_template;

  INSERT INTO public.starter_pack_template_items(template_id, player_id, slot)
  SELECT
    _fixture_template,
    p.id,
    pg_catalog.row_number() OVER (ORDER BY p.code)::smallint
  FROM public.players p
  WHERE p.code LIKE 'FSPK%';

  INSERT INTO public.initial_packs(id, club_id, starter_pack_template_id)
  VALUES (_fixture_pack, _fixture_club, _fixture_template);

  SELECT cp.id
  INTO _blocked_card
  FROM public.club_players cp
  JOIN public.players p ON p.id = cp.player_id
  WHERE p.code = 'FSPK01';

  UPDATE public.system_market_stock
  SET is_market_eligible = true
  WHERE club_player_id = _blocked_card;

  PERFORM pg_catalog.set_config('request.jwt.claim.sub', _fixture_user::text, true);

  BEGIN
    PERFORM * FROM public.open_initial_pack(_fixture_club);
    RAISE EXCEPTION 'assertion_failed: commercial card entered starter pack';
  EXCEPTION
    WHEN OTHERS THEN
      GET STACKED DIAGNOSTICS _message = MESSAGE_TEXT;
      IF _message <> 'starter_pack_card_unavailable' THEN
        RAISE;
      END IF;
  END;

  IF EXISTS (
    SELECT 1
    FROM public.club_players cp
    WHERE cp.club_id = _fixture_club
  ) OR EXISTS (
    SELECT 1
    FROM public.initial_pack_items ipi
    WHERE ipi.pack_id = _fixture_pack
  ) OR EXISTS (
    SELECT 1
    FROM public.initial_packs ip
    WHERE ip.id = _fixture_pack
      AND ip.opened_at IS NOT NULL
  ) THEN
    RAISE EXCEPTION 'assertion_failed: failed opening was not atomic';
  END IF;

  UPDATE public.system_market_stock
  SET is_market_eligible = false
  WHERE club_player_id = _blocked_card;

  SELECT
    pg_catalog.array_agg(p.code ORDER BY opened.slot),
    pg_catalog.count(*)::integer
  INTO _opened_codes, _count
  FROM public.open_initial_pack(_fixture_club) opened
  JOIN public.players p ON p.id = opened.player_id;

  IF _count <> 10 OR _opened_codes <> ARRAY[
    'FSPK01','FSPK02','FSPK03','FSPK04','FSPK05',
    'FSPK06','FSPK07','FSPK08','FSPK09','FSPK10'
  ]::text[] THEN
    RAISE EXCEPTION 'assertion_failed: opened package mismatch, got %', _opened_codes;
  END IF;

  IF (
    SELECT pg_catalog.count(*)
    FROM public.club_players cp
    WHERE cp.club_id = _fixture_club
  ) <> 10 THEN
    RAISE EXCEPTION 'assertion_failed: package did not transfer ten cards';
  END IF;

  IF EXISTS (
    SELECT 1
    FROM public.system_market_stock sms
    JOIN public.club_players cp ON cp.id = sms.club_player_id
    JOIN public.players p ON p.id = cp.player_id
    WHERE p.code LIKE 'FSPK%'
  ) THEN
    RAISE EXCEPTION 'assertion_failed: opened cards remained in system stock';
  END IF;

  SELECT pg_catalog.array_agg(p.code ORDER BY opened.slot)
  INTO _opened_again
  FROM public.open_initial_pack(_fixture_club) opened
  JOIN public.players p ON p.id = opened.player_id;

  IF _opened_again <> _opened_codes THEN
    RAISE EXCEPTION 'assertion_failed: repeated opening changed package';
  END IF;

  IF (
    SELECT pg_catalog.count(*)
    FROM public.initial_pack_items ipi
    WHERE ipi.pack_id = _fixture_pack
  ) <> 10 THEN
    RAISE EXCEPTION 'assertion_failed: repeated opening duplicated items';
  END IF;

  RAISE NOTICE 'fair_starter_packs contract test passed';
END;
$$;

ROLLBACK;
