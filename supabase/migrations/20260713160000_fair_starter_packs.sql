-- =====================================================================
-- BAGREFUT - Fair, exclusive starter packs and deterministic opening
-- Forward-only migration. Do not edit previously applied migrations.
-- =====================================================================

-- ---------------------------------------------------------------------
-- Preflight: current data must be fully reset before assigning templates.
-- ---------------------------------------------------------------------
DO $$
DECLARE
  _codes text[] := ARRAY[
    'GK05','GK11','DEF11','DEF09','DEF03','MID04','MID14','MID13','ATA01','ATA12',
    'GK01','GK03','DEF05','DEF02','DEF16','MID08','MID09','MID18','ATA07','ATA08',
    'GK02','GK12','DEF10','DEF14','DEF13','MID05','MID06','MID15','ATA04','ATA03',
    'GK06','GK09','DEF07','DEF08','DEF18','MID07','MID02','MID12','ATA06','ATA09',
    'GK07','GK10','DEF01','DEF17','DEF12','MID10','MID03','MID17','ATA02','ATA11',
    'GK04','GK08','DEF04','DEF06','DEF15','MID01','MID11','MID16','ATA05','ATA10'
  ];
BEGIN
  IF (SELECT pg_catalog.count(*) FROM public.clubs) > 6 THEN
    RAISE EXCEPTION 'fair_starter_packs_more_than_six_clubs';
  END IF;

  IF (SELECT pg_catalog.count(*) FROM public.initial_packs)
     <> (SELECT pg_catalog.count(*) FROM public.clubs) THEN
    RAISE EXCEPTION 'fair_starter_packs_missing_initial_pack';
  END IF;

  IF EXISTS (
    SELECT 1
    FROM public.initial_packs ip
    WHERE ip.opened_at IS NOT NULL
  ) THEN
    RAISE EXCEPTION 'fair_starter_packs_opened_pack_exists';
  END IF;

  IF EXISTS (
    SELECT 1
    FROM public.club_players cp
    WHERE cp.club_id IS NOT NULL
  ) THEN
    RAISE EXCEPTION 'fair_starter_packs_owned_card_exists';
  END IF;

  IF pg_catalog.cardinality(_codes) <> 60
     OR (SELECT pg_catalog.count(DISTINCT code) FROM pg_catalog.unnest(_codes) AS code) <> 60 THEN
    RAISE EXCEPTION 'fair_starter_packs_invalid_definition';
  END IF;

  IF (
    SELECT pg_catalog.count(*)
    FROM public.players p
    WHERE p.code = ANY(_codes)
  ) <> 60 THEN
    RAISE EXCEPTION 'fair_starter_packs_player_code_missing';
  END IF;

  IF (
    SELECT pg_catalog.count(*)
    FROM public.players p
    JOIN public.club_players cp ON cp.player_id = p.id
    JOIN public.system_market_stock sms ON sms.club_player_id = cp.id
    WHERE p.code = ANY(_codes)
      AND cp.club_id IS NULL
      AND NOT cp.is_reserved
      AND NOT sms.is_market_eligible
  ) <> 60 THEN
    RAISE EXCEPTION 'fair_starter_packs_card_not_in_initial_pool';
  END IF;

  IF (SELECT pg_catalog.sum(p.overall) FROM public.players p WHERE p.code = ANY(ARRAY['GK05','GK11','DEF11','DEF09','DEF03','MID04','MID14','MID13','ATA01','ATA12'])) <> 579
     OR (SELECT pg_catalog.sum(p.overall) FROM public.players p WHERE p.code = ANY(ARRAY['GK01','GK03','DEF05','DEF02','DEF16','MID08','MID09','MID18','ATA07','ATA08'])) <> 578
     OR (SELECT pg_catalog.sum(p.overall) FROM public.players p WHERE p.code = ANY(ARRAY['GK02','GK12','DEF10','DEF14','DEF13','MID05','MID06','MID15','ATA04','ATA03'])) <> 579
     OR (SELECT pg_catalog.sum(p.overall) FROM public.players p WHERE p.code = ANY(ARRAY['GK06','GK09','DEF07','DEF08','DEF18','MID07','MID02','MID12','ATA06','ATA09'])) <> 579
     OR (SELECT pg_catalog.sum(p.overall) FROM public.players p WHERE p.code = ANY(ARRAY['GK07','GK10','DEF01','DEF17','DEF12','MID10','MID03','MID17','ATA02','ATA11'])) <> 578
     OR (SELECT pg_catalog.sum(p.overall) FROM public.players p WHERE p.code = ANY(ARRAY['GK04','GK08','DEF04','DEF06','DEF15','MID01','MID11','MID16','ATA05','ATA10'])) <> 579 THEN
    RAISE EXCEPTION 'fair_starter_packs_overall_mismatch';
  END IF;
END;
$$;

-- ---------------------------------------------------------------------
-- Private package templates. Client code never reads these tables.
-- ---------------------------------------------------------------------
CREATE TABLE public.starter_pack_templates (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  code text NOT NULL UNIQUE,
  expected_total_overall smallint NOT NULL,
  expected_starter_overall smallint NOT NULL,
  created_at timestamptz NOT NULL DEFAULT pg_catalog.now(),
  CONSTRAINT starter_pack_templates_code_format
    CHECK (code ~ '^[A-Z0-9_]{4,32}$')
);

CREATE TABLE public.starter_pack_template_items (
  template_id uuid NOT NULL
    REFERENCES public.starter_pack_templates(id) ON DELETE CASCADE,
  player_id uuid NOT NULL
    REFERENCES public.players(id) ON DELETE RESTRICT,
  slot smallint NOT NULL CHECK (slot BETWEEN 1 AND 10),
  PRIMARY KEY (template_id, slot),
  CONSTRAINT starter_pack_template_items_player_unique UNIQUE (player_id)
);

GRANT ALL ON public.starter_pack_templates TO service_role;
GRANT ALL ON public.starter_pack_template_items TO service_role;
REVOKE ALL ON public.starter_pack_templates FROM PUBLIC, anon, authenticated;
REVOKE ALL ON public.starter_pack_template_items FROM PUBLIC, anon, authenticated;
ALTER TABLE public.starter_pack_templates ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.starter_pack_template_items ENABLE ROW LEVEL SECURITY;

ALTER TABLE public.initial_packs
  ADD COLUMN starter_pack_template_id uuid NULL
  REFERENCES public.starter_pack_templates(id) ON DELETE RESTRICT;

ALTER TABLE public.initial_packs
  ADD CONSTRAINT initial_packs_starter_pack_template_unique
  UNIQUE (starter_pack_template_id);

-- ---------------------------------------------------------------------
-- Exact six package definitions. Slot order follows supplied GK/DEF/MID/ATA
-- order and is persisted into initial_pack_items when opened.
-- ---------------------------------------------------------------------
WITH definitions(code, total_overall, starter_overall, player_codes) AS (
  VALUES
    ('PACK01', 579::smallint, 335::smallint, ARRAY['GK05','GK11','DEF11','DEF09','DEF03','MID04','MID14','MID13','ATA01','ATA12']::text[]),
    ('PACK02', 578::smallint, 335::smallint, ARRAY['GK01','GK03','DEF05','DEF02','DEF16','MID08','MID09','MID18','ATA07','ATA08']::text[]),
    ('PACK03', 579::smallint, 336::smallint, ARRAY['GK02','GK12','DEF10','DEF14','DEF13','MID05','MID06','MID15','ATA04','ATA03']::text[]),
    ('PACK04', 579::smallint, 336::smallint, ARRAY['GK06','GK09','DEF07','DEF08','DEF18','MID07','MID02','MID12','ATA06','ATA09']::text[]),
    ('PACK05', 578::smallint, 336::smallint, ARRAY['GK07','GK10','DEF01','DEF17','DEF12','MID10','MID03','MID17','ATA02','ATA11']::text[]),
    ('PACK06', 579::smallint, 336::smallint, ARRAY['GK04','GK08','DEF04','DEF06','DEF15','MID01','MID11','MID16','ATA05','ATA10']::text[])
), inserted_templates AS (
  INSERT INTO public.starter_pack_templates(
    code,
    expected_total_overall,
    expected_starter_overall
  )
  SELECT d.code, d.total_overall, d.starter_overall
  FROM definitions d
  RETURNING id, code
)
INSERT INTO public.starter_pack_template_items(template_id, player_id, slot)
SELECT
  t.id,
  p.id,
  item.slot::smallint
FROM definitions d
JOIN inserted_templates t ON t.code = d.code
CROSS JOIN LATERAL pg_catalog.unnest(d.player_codes)
  WITH ORDINALITY AS item(player_code, slot)
JOIN public.players p ON p.code = item.player_code;

DO $$
BEGIN
  IF (SELECT pg_catalog.count(*) FROM public.starter_pack_templates WHERE code ~ '^PACK0[1-6]$') <> 6
     OR (
       SELECT pg_catalog.count(*)
       FROM public.starter_pack_template_items i
       JOIN public.starter_pack_templates t ON t.id = i.template_id
       WHERE t.code ~ '^PACK0[1-6]$'
     ) <> 60 THEN
    RAISE EXCEPTION 'fair_starter_packs_seed_failed';
  END IF;

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
    RAISE EXCEPTION 'fair_starter_packs_seed_invalid';
  END IF;
END;
$$;

-- Random one-to-one backfill for existing reset clubs.
WITH ranked_packs AS (
  SELECT
    ip.id,
    pg_catalog.row_number() OVER (ORDER BY pg_catalog.random(), ip.id) AS rn
  FROM public.initial_packs ip
), ranked_templates AS (
  SELECT
    t.id,
    pg_catalog.row_number() OVER (ORDER BY pg_catalog.random(), t.id) AS rn
  FROM public.starter_pack_templates t
  WHERE t.code ~ '^PACK0[1-6]$'
)
UPDATE public.initial_packs ip
SET starter_pack_template_id = rt.id
FROM ranked_packs rp
JOIN ranked_templates rt ON rt.rn = rp.rn
WHERE ip.id = rp.id;

ALTER TABLE public.initial_packs
  ALTER COLUMN starter_pack_template_id SET NOT NULL;

-- ---------------------------------------------------------------------
-- Club creation reserves one free template in the same transaction.
-- Existing identity validation behavior is preserved.
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.create_club(
  _name text,
  _abbreviation text,
  _badge_code text
)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  _uid uuid := auth.uid();
  _profile public.profiles%ROWTYPE;
  _league public.leagues%ROWTYPE;
  _badge public.club_badges%ROWTYPE;
  _name_clean text;
  _normalized_name text;
  _abbr text;
  _club_id uuid;
  _template_id uuid;
BEGIN
  IF _uid IS NULL THEN
    RAISE EXCEPTION 'unauthenticated';
  END IF;

  SELECT *
  INTO _profile
  FROM public.profiles p
  WHERE p.id = _uid
  FOR UPDATE;

  IF _profile.id IS NULL THEN
    RAISE EXCEPTION 'profile_not_found';
  END IF;
  IF _profile.status <> 'approved' THEN
    RAISE EXCEPTION 'profile_not_approved';
  END IF;

  IF EXISTS (SELECT 1 FROM public.clubs c WHERE c.owner_id = _uid) THEN
    RAISE EXCEPTION 'club_already_exists';
  END IF;

  SELECT *
  INTO _league
  FROM public.leagues l
  WHERE l.slug = 'bagreleirao'
  FOR UPDATE;

  IF _league.id IS NULL THEN
    RAISE EXCEPTION 'league_missing';
  END IF;
  IF _league.status <> 'setup' THEN
    RAISE EXCEPTION 'league_not_in_setup';
  END IF;
  IF (
    SELECT pg_catalog.count(*)
    FROM public.clubs c
    WHERE c.league_id = _league.id
  ) >= _league.max_clubs THEN
    RAISE EXCEPTION 'league_full';
  END IF;

  IF _name IS NULL OR pg_catalog.btrim(_name) = '' THEN
    RAISE EXCEPTION 'club_name_required';
  END IF;

  _name_clean := pg_catalog.regexp_replace(pg_catalog.btrim(_name), '[[:space:]]+', ' ', 'g');
  _normalized_name := public.normalize_club_name(_name_clean);

  IF pg_catalog.char_length(_name_clean) < 3 OR pg_catalog.char_length(_name_clean) > 24 THEN
    RAISE EXCEPTION 'club_name_invalid_length';
  END IF;
  IF _name_clean !~ '^[[:alpha:][:digit:] ]+$' THEN
    RAISE EXCEPTION 'club_name_invalid_characters';
  END IF;

  IF _abbreviation IS NULL OR pg_catalog.btrim(_abbreviation) = '' THEN
    RAISE EXCEPTION 'club_abbreviation_required';
  END IF;

  _abbr := pg_catalog.upper(pg_catalog.btrim(_abbreviation));
  IF _abbr !~ '^[A-Z]{2,4}$' THEN
    RAISE EXCEPTION 'club_abbreviation_invalid';
  END IF;

  IF EXISTS (
    SELECT 1
    FROM public.clubs c
    WHERE c.league_id = _league.id
      AND c.normalized_name = _normalized_name
  ) THEN
    RAISE EXCEPTION 'club_name_already_exists';
  END IF;

  IF EXISTS (
    SELECT 1
    FROM public.clubs c
    WHERE c.league_id = _league.id
      AND c.abbreviation = _abbr
  ) THEN
    RAISE EXCEPTION 'club_abbreviation_already_exists';
  END IF;

  SELECT *
  INTO _badge
  FROM public.club_badges b
  WHERE b.code = _badge_code;

  IF _badge.id IS NULL THEN
    RAISE EXCEPTION 'club_badge_not_found';
  END IF;
  IF NOT _badge.is_active THEN
    RAISE EXCEPTION 'club_badge_inactive';
  END IF;

  SELECT t.id
  INTO _template_id
  FROM public.starter_pack_templates t
  WHERE NOT EXISTS (
    SELECT 1
    FROM public.initial_packs ip
    WHERE ip.starter_pack_template_id = t.id
  )
  ORDER BY pg_catalog.random(), t.id
  LIMIT 1
  FOR UPDATE OF t SKIP LOCKED;

  IF _template_id IS NULL THEN
    RAISE EXCEPTION 'starter_pack_templates_exhausted';
  END IF;

  INSERT INTO public.clubs(
    league_id,
    owner_id,
    name,
    normalized_name,
    abbreviation,
    badge_id,
    balance_cents
  )
  VALUES (
    _league.id,
    _uid,
    _name_clean,
    _normalized_name,
    _abbr,
    _badge.id,
    0
  )
  RETURNING id INTO _club_id;

  PERFORM public._credit_wallet(
    _club_id,
    1000,
    'initial_credit',
    'clubs',
    _club_id,
    'saldo inicial'
  );

  INSERT INTO public.initial_packs(club_id, starter_pack_template_id)
  VALUES (_club_id, _template_id);

  RETURN _club_id;
END;
$$;

REVOKE ALL ON FUNCTION public.create_club(text, text, text)
  FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.create_club(text, text, text)
  TO authenticated;

-- ---------------------------------------------------------------------
-- Opening consumes the exact assigned template. Repeated calls are
-- idempotent and return the already-recorded same ten items.
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.open_initial_pack(_club_id uuid)
RETURNS TABLE(
  pack_id uuid,
  club_id uuid,
  opened_at timestamptz,
  player_id uuid,
  slot smallint
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  _uid uuid := auth.uid();
  _profile public.profiles%ROWTYPE;
  _club public.clubs%ROWTYPE;
  _league public.leagues%ROWTYPE;
  _pack public.initial_packs%ROWTYPE;
  _opened_at timestamptz;
  _current_roster integer;
  _template_count integer;
  _available_count integer;
  _affected integer;
BEGIN
  IF _uid IS NULL THEN
    RAISE EXCEPTION 'unauthenticated';
  END IF;

  SELECT *
  INTO _profile
  FROM public.profiles p
  WHERE p.id = _uid;

  IF _profile.id IS NULL THEN
    RAISE EXCEPTION 'profile_not_found';
  END IF;
  IF _profile.status <> 'approved' THEN
    RAISE EXCEPTION 'profile_not_approved';
  END IF;

  SELECT *
  INTO _club
  FROM public.clubs c
  WHERE c.id = _club_id
  FOR UPDATE;

  IF _club.id IS NULL THEN
    RAISE EXCEPTION 'club_not_found';
  END IF;
  IF _club.owner_id <> _uid THEN
    RAISE EXCEPTION 'not_club_owner';
  END IF;

  SELECT *
  INTO _league
  FROM public.leagues l
  WHERE l.id = _club.league_id;

  IF _league.id IS NULL THEN
    RAISE EXCEPTION 'league_not_found';
  END IF;
  IF _league.status <> 'setup' THEN
    RAISE EXCEPTION 'league_not_in_setup';
  END IF;

  SELECT *
  INTO _pack
  FROM public.initial_packs ip
  WHERE ip.club_id = _club_id
  FOR UPDATE;

  IF _pack.id IS NULL THEN
    RAISE EXCEPTION 'pack_not_found';
  END IF;
  IF _pack.starter_pack_template_id IS NULL THEN
    RAISE EXCEPTION 'starter_pack_template_missing';
  END IF;

  IF _pack.opened_at IS NOT NULL THEN
    IF (
      SELECT pg_catalog.count(*)
      FROM public.initial_pack_items ipi
      WHERE ipi.pack_id = _pack.id
    ) <> 10 THEN
      RAISE EXCEPTION 'starter_pack_template_invalid';
    END IF;

    RETURN QUERY
    SELECT
      _pack.id,
      _club_id,
      _pack.opened_at,
      ipi.player_id,
      ipi.slot
    FROM public.initial_pack_items ipi
    WHERE ipi.pack_id = _pack.id
    ORDER BY ipi.slot;
    RETURN;
  END IF;

  SELECT pg_catalog.count(*)::integer
  INTO _current_roster
  FROM public.club_players cp
  WHERE cp.club_id = _club.id;

  IF _current_roster <> 0 THEN
    RAISE EXCEPTION 'initial_pack_requires_empty_roster';
  END IF;

  SELECT pg_catalog.count(*)::integer
  INTO _template_count
  FROM public.starter_pack_template_items i
  WHERE i.template_id = _pack.starter_pack_template_id;

  IF _template_count <> 10 THEN
    RAISE EXCEPTION 'starter_pack_template_invalid';
  END IF;

  PERFORM 1
  FROM public.starter_pack_template_items i
  JOIN public.club_players cp ON cp.player_id = i.player_id
  JOIN public.system_market_stock sms ON sms.club_player_id = cp.id
  WHERE i.template_id = _pack.starter_pack_template_id
  ORDER BY i.slot
  FOR UPDATE OF cp, sms;

  SELECT pg_catalog.count(*)::integer
  INTO _available_count
  FROM public.starter_pack_template_items i
  JOIN public.club_players cp ON cp.player_id = i.player_id
  JOIN public.system_market_stock sms ON sms.club_player_id = cp.id
  WHERE i.template_id = _pack.starter_pack_template_id
    AND cp.club_id IS NULL
    AND NOT cp.is_reserved
    AND NOT sms.is_market_eligible;

  IF _available_count <> 10 THEN
    RAISE EXCEPTION 'starter_pack_card_unavailable';
  END IF;

  DELETE FROM public.system_market_stock sms
  USING public.club_players cp, public.starter_pack_template_items i
  WHERE sms.club_player_id = cp.id
    AND cp.player_id = i.player_id
    AND i.template_id = _pack.starter_pack_template_id
    AND NOT sms.is_market_eligible;

  GET DIAGNOSTICS _affected = ROW_COUNT;
  IF _affected <> 10 THEN
    RAISE EXCEPTION 'starter_pack_card_unavailable';
  END IF;

  UPDATE public.club_players cp
  SET club_id = _club_id,
      acquired_at = pg_catalog.now(),
      is_reserved = false
  FROM public.starter_pack_template_items i
  WHERE cp.player_id = i.player_id
    AND i.template_id = _pack.starter_pack_template_id
    AND cp.club_id IS NULL;

  GET DIAGNOSTICS _affected = ROW_COUNT;
  IF _affected <> 10 THEN
    RAISE EXCEPTION 'starter_pack_card_unavailable';
  END IF;

  INSERT INTO public.initial_pack_items(pack_id, player_id, slot)
  SELECT _pack.id, i.player_id, i.slot
  FROM public.starter_pack_template_items i
  WHERE i.template_id = _pack.starter_pack_template_id
  ORDER BY i.slot;

  UPDATE public.initial_packs ip
  SET opened_at = pg_catalog.now()
  WHERE ip.id = _pack.id
    AND ip.opened_at IS NULL
  RETURNING ip.opened_at INTO _opened_at;

  IF _opened_at IS NULL THEN
    RAISE EXCEPTION 'pack_already_opened';
  END IF;

  RETURN QUERY
  SELECT
    _pack.id,
    _club_id,
    _opened_at,
    ipi.player_id,
    ipi.slot
  FROM public.initial_pack_items ipi
  WHERE ipi.pack_id = _pack.id
  ORDER BY ipi.slot;
END;
$$;

REVOKE ALL ON FUNCTION public.open_initial_pack(uuid)
  FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.open_initial_pack(uuid)
  TO authenticated;
