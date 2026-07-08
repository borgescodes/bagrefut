-- =====================================================================
-- BAGREFUT - Fix club identity normalization, validation, and badge catalog
-- =====================================================================

CREATE OR REPLACE FUNCTION public.normalize_club_name(_name text)
RETURNS text
LANGUAGE sql
IMMUTABLE
SET search_path = ''
AS $$
  SELECT CASE
    WHEN _name IS NULL THEN NULL
    ELSE pg_catalog.lower(pg_catalog.regexp_replace(pg_catalog.btrim(_name), '[[:space:]]+', ' ', 'g'))
  END
$$;

REVOKE ALL ON FUNCTION public.normalize_club_name(text) FROM PUBLIC, anon, authenticated;

ALTER TABLE public.clubs
  ADD COLUMN IF NOT EXISTS normalized_name text;

UPDATE public.clubs
SET name = pg_catalog.regexp_replace(pg_catalog.btrim(name), '[[:space:]]+', ' ', 'g'),
    normalized_name = public.normalize_club_name(name);

DO $$
DECLARE
  _bad record;
BEGIN
  SELECT c.id
  INTO _bad
  FROM public.clubs c
  WHERE c.name IS NULL
     OR c.name = ''
     OR pg_catalog.char_length(c.name) < 3
     OR pg_catalog.char_length(c.name) > 24
     OR c.name !~ '^[[:alpha:][:digit:] ]+$'
  LIMIT 1;

  IF FOUND THEN
    RAISE EXCEPTION 'existing_club_name_invalid';
  END IF;

  SELECT c.id
  INTO _bad
  FROM public.clubs c
  WHERE c.abbreviation IS NULL
     OR c.abbreviation !~ '^[A-Z]{2,4}$'
  LIMIT 1;

  IF FOUND THEN
    RAISE EXCEPTION 'existing_club_abbreviation_invalid';
  END IF;

  SELECT d.league_id, d.normalized_name
  INTO _bad
  FROM (
    SELECT c.league_id, c.normalized_name
    FROM public.clubs c
    GROUP BY c.league_id, c.normalized_name
    HAVING pg_catalog.count(*) > 1
  ) d
  LIMIT 1;

  IF FOUND THEN
    RAISE EXCEPTION 'existing_club_name_duplicate';
  END IF;

  SELECT d.league_id, d.abbreviation
  INTO _bad
  FROM (
    SELECT c.league_id, c.abbreviation
    FROM public.clubs c
    GROUP BY c.league_id, c.abbreviation
    HAVING pg_catalog.count(*) > 1
  ) d
  LIMIT 1;

  IF FOUND THEN
    RAISE EXCEPTION 'existing_club_abbreviation_duplicate';
  END IF;
END;
$$;

ALTER TABLE public.clubs
  ALTER COLUMN normalized_name SET NOT NULL;

CREATE UNIQUE INDEX IF NOT EXISTS idx_clubs_league_normalized_name_unique
  ON public.clubs (league_id, normalized_name);

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1
    FROM pg_catalog.pg_constraint
    WHERE conrelid = 'public.clubs'::regclass
      AND conname = 'clubs_name_normalized_valid'
  ) THEN
    ALTER TABLE public.clubs
      ADD CONSTRAINT clubs_name_normalized_valid
      CHECK (
        name = pg_catalog.regexp_replace(pg_catalog.btrim(name), '[[:space:]]+', ' ', 'g')
        AND public.normalize_club_name(name) = normalized_name
        AND pg_catalog.char_length(name) BETWEEN 3 AND 24
        AND name ~ '^[[:alpha:][:digit:] ]+$'
      );
  END IF;

  IF NOT EXISTS (
    SELECT 1
    FROM pg_catalog.pg_constraint
    WHERE conrelid = 'public.clubs'::regclass
      AND conname = 'clubs_abbreviation_upper_valid'
  ) THEN
    ALTER TABLE public.clubs
      ADD CONSTRAINT clubs_abbreviation_upper_valid
      CHECK (
        abbreviation = pg_catalog.upper(abbreviation)
        AND abbreviation ~ '^[A-Z]{2,4}$'
      );
  END IF;
END;
$$;

WITH new_badges AS (
  SELECT
    'badge-' || (CASE WHEN g.i < 100 THEN pg_catalog.lpad(g.i::text, 2, '0') ELSE g.i::text END) AS code,
    'Escudo ' || (CASE WHEN g.i < 100 THEN pg_catalog.lpad(g.i::text, 2, '0') ELSE g.i::text END) AS label,
    '/badges/badge-' || (CASE WHEN g.i < 100 THEN pg_catalog.lpad(g.i::text, 2, '0') ELSE g.i::text END) || '.png' AS asset_path,
    g.i AS sort_order,
    true AS is_active
  FROM pg_catalog.generate_series(1, 66) AS g(i)
)
INSERT INTO public.club_badges (code, label, asset_path, sort_order, is_active)
SELECT nb.code, nb.label, nb.asset_path, nb.sort_order, nb.is_active
FROM new_badges nb
ON CONFLICT (code) DO UPDATE
SET label = EXCLUDED.label,
    asset_path = EXCLUDED.asset_path,
    sort_order = EXCLUDED.sort_order,
    is_active = EXCLUDED.is_active;

WITH new_badges AS (
  SELECT 'badge-' || (CASE WHEN g.i < 100 THEN pg_catalog.lpad(g.i::text, 2, '0') ELSE g.i::text END) AS code
  FROM pg_catalog.generate_series(1, 66) AS g(i)
)
UPDATE public.club_badges b
SET is_active = false
WHERE NOT EXISTS (
  SELECT 1
  FROM new_badges nb
  WHERE nb.code = b.code
);

CREATE OR REPLACE FUNCTION public.create_club(
  _name text, _abbreviation text, _badge_code text
) RETURNS uuid
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
BEGIN
  IF _uid IS NULL THEN
    RAISE EXCEPTION 'unauthenticated';
  END IF;

  SELECT *
  INTO _profile
  FROM public.profiles
  WHERE id = _uid
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
  FROM public.leagues
  WHERE slug = 'bagreleirao'
  FOR UPDATE;

  IF _league.id IS NULL THEN
    RAISE EXCEPTION 'league_missing';
  END IF;

  IF _league.status <> 'setup' THEN
    RAISE EXCEPTION 'league_not_in_setup';
  END IF;

  IF (SELECT pg_catalog.count(*) FROM public.clubs c WHERE c.league_id = _league.id) >= _league.max_clubs THEN
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
  FROM public.club_badges
  WHERE code = _badge_code;

  IF _badge.id IS NULL THEN
    RAISE EXCEPTION 'club_badge_not_found';
  END IF;

  IF NOT _badge.is_active THEN
    RAISE EXCEPTION 'club_badge_inactive';
  END IF;

  INSERT INTO public.clubs (
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

  PERFORM public._credit_wallet(_club_id, 1000, 'initial_credit', 'clubs', _club_id, 'saldo inicial');

  INSERT INTO public.initial_packs (club_id)
  VALUES (_club_id);

  RETURN _club_id;
END;
$$;

REVOKE ALL ON FUNCTION public.create_club(text, text, text) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.create_club(text, text, text) TO authenticated;

DROP FUNCTION IF EXISTS public.update_club_identity(uuid, text, text, text);

CREATE OR REPLACE FUNCTION public.update_club_identity(
  _club_id uuid,
  _name text DEFAULT NULL,
  _abbreviation text DEFAULT NULL,
  _badge_code text DEFAULT NULL
)
RETURNS TABLE(
  club_id uuid,
  name text,
  normalized_name text,
  abbreviation text,
  badge_id uuid,
  updated_at timestamptz
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
  _badge public.club_badges%ROWTYPE;
  _is_admin boolean := false;
  _new_name text;
  _new_normalized_name text;
  _new_abbreviation text;
  _new_badge_id uuid;
  _changed_at timestamptz := pg_catalog.now();
  _out_club_id uuid;
  _out_name text;
  _out_normalized_name text;
  _out_abbreviation text;
  _out_badge_id uuid;
  _out_updated_at timestamptz;
BEGIN
  IF _uid IS NULL THEN
    RAISE EXCEPTION 'unauthenticated';
  END IF;

  IF _club_id IS NULL THEN
    RAISE EXCEPTION 'club_not_found';
  END IF;

  IF _name IS NULL AND _abbreviation IS NULL AND _badge_code IS NULL THEN
    RAISE EXCEPTION 'no_changes_provided';
  END IF;

  SELECT *
  INTO _profile
  FROM public.profiles
  WHERE id = _uid;

  IF _profile.id IS NULL THEN
    RAISE EXCEPTION 'profile_not_found';
  END IF;

  IF _profile.status <> 'approved' THEN
    RAISE EXCEPTION 'profile_not_approved';
  END IF;

  _is_admin := public.has_role(_uid, 'admin'::public.app_role);

  SELECT *
  INTO _club
  FROM public.clubs
  WHERE id = _club_id
  FOR UPDATE;

  IF _club.id IS NULL THEN
    RAISE EXCEPTION 'club_not_found';
  END IF;

  SELECT *
  INTO _league
  FROM public.leagues
  WHERE id = _club.league_id
  FOR UPDATE;

  IF _league.id IS NULL THEN
    RAISE EXCEPTION 'league_missing';
  END IF;

  IF NOT _is_admin THEN
    IF _club.owner_id <> _uid THEN
      RAISE EXCEPTION 'forbidden_not_club_owner';
    END IF;

    IF _league.status <> 'setup' THEN
      RAISE EXCEPTION 'club_identity_locked';
    END IF;
  END IF;

  _new_name := _club.name;
  _new_normalized_name := _club.normalized_name;
  _new_abbreviation := _club.abbreviation;
  _new_badge_id := _club.badge_id;

  IF _name IS NOT NULL THEN
    IF pg_catalog.btrim(_name) = '' THEN
      RAISE EXCEPTION 'club_name_required';
    END IF;

    _new_name := pg_catalog.regexp_replace(pg_catalog.btrim(_name), '[[:space:]]+', ' ', 'g');
    _new_normalized_name := public.normalize_club_name(_new_name);

    IF pg_catalog.char_length(_new_name) < 3 OR pg_catalog.char_length(_new_name) > 24 THEN
      RAISE EXCEPTION 'club_name_invalid_length';
    END IF;

    IF _new_name !~ '^[[:alpha:][:digit:] ]+$' THEN
      RAISE EXCEPTION 'club_name_invalid_characters';
    END IF;
  END IF;

  IF _abbreviation IS NOT NULL THEN
    IF pg_catalog.btrim(_abbreviation) = '' THEN
      RAISE EXCEPTION 'club_abbreviation_required';
    END IF;

    _new_abbreviation := pg_catalog.upper(pg_catalog.btrim(_abbreviation));

    IF _new_abbreviation !~ '^[A-Z]{2,4}$' THEN
      RAISE EXCEPTION 'club_abbreviation_invalid';
    END IF;
  END IF;

  IF _badge_code IS NOT NULL THEN
    SELECT *
    INTO _badge
    FROM public.club_badges
    WHERE code = _badge_code;

    IF _badge.id IS NULL THEN
      RAISE EXCEPTION 'club_badge_not_found';
    END IF;

    IF NOT _badge.is_active THEN
      RAISE EXCEPTION 'club_badge_inactive';
    END IF;

    _new_badge_id := _badge.id;
  END IF;

  IF EXISTS (
    SELECT 1
    FROM public.clubs c
    WHERE c.league_id = _club.league_id
      AND c.id <> _club.id
      AND c.normalized_name = _new_normalized_name
  ) THEN
    RAISE EXCEPTION 'club_name_already_exists';
  END IF;

  IF EXISTS (
    SELECT 1
    FROM public.clubs c
    WHERE c.league_id = _club.league_id
      AND c.id <> _club.id
      AND c.abbreviation = _new_abbreviation
  ) THEN
    RAISE EXCEPTION 'club_abbreviation_already_exists';
  END IF;

  IF _new_name = _club.name
     AND _new_normalized_name = _club.normalized_name
     AND _new_abbreviation = _club.abbreviation
     AND _new_badge_id = _club.badge_id THEN
    RAISE EXCEPTION 'no_changes_provided';
  END IF;

  UPDATE public.clubs c
  SET name = _new_name,
      normalized_name = _new_normalized_name,
      abbreviation = _new_abbreviation,
      badge_id = _new_badge_id,
      updated_at = _changed_at
  WHERE c.id = _club.id
  RETURNING c.id, c.name, c.normalized_name, c.abbreviation, c.badge_id, c.updated_at
  INTO _out_club_id, _out_name, _out_normalized_name, _out_abbreviation, _out_badge_id, _out_updated_at;

  IF _is_admin AND _club.owner_id <> _uid THEN
    INSERT INTO public.admin_audit_logs (
      admin_id,
      action,
      target_table,
      target_id,
      payload,
      created_at
    )
    VALUES (
      _uid,
      'admin_update_club_identity',
      'clubs',
      _club.id,
      pg_catalog.jsonb_build_object(
        'actor_user_id', _uid,
        'previous_name', _club.name,
        'new_name', _new_name,
        'previous_abbreviation', _club.abbreviation,
        'new_abbreviation', _new_abbreviation,
        'previous_badge_id', _club.badge_id,
        'new_badge_id', _new_badge_id,
        'league_status', _league.status,
        'changed_at', _changed_at
      ),
      _changed_at
    );
  END IF;

  RETURN QUERY
  SELECT
    _out_club_id,
    _out_name,
    _out_normalized_name,
    _out_abbreviation,
    _out_badge_id,
    _out_updated_at;
END;
$$;

REVOKE ALL ON FUNCTION public.update_club_identity(uuid, text, text, text) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.update_club_identity(uuid, text, text, text) TO authenticated;

REVOKE INSERT, UPDATE, DELETE, TRUNCATE, REFERENCES, TRIGGER ON TABLE public.clubs FROM authenticated;
REVOKE INSERT, UPDATE, DELETE, TRUNCATE, REFERENCES, TRIGGER ON TABLE public.club_badges FROM authenticated;

GRANT SELECT ON TABLE public.clubs TO authenticated;
GRANT SELECT ON TABLE public.club_badges TO authenticated;

DROP POLICY IF EXISTS "club_badges_authenticated_read" ON public.club_badges;
DROP POLICY IF EXISTS "club_badges_approved_read" ON public.club_badges;
DROP POLICY IF EXISTS "club_badges_approved_active_or_admin_read" ON public.club_badges;

CREATE POLICY "club_badges_approved_active_or_admin_read"
ON public.club_badges
FOR SELECT
TO authenticated
USING (
  public.is_approved_user(auth.uid())
  AND (
    is_active
    OR public.has_role(auth.uid(), 'admin'::public.app_role)
  )
);

DROP POLICY IF EXISTS "clubs_authenticated_read" ON public.clubs;
DROP POLICY IF EXISTS "clubs_approved_read" ON public.clubs;

CREATE POLICY "clubs_approved_read"
ON public.clubs
FOR SELECT
TO authenticated
USING (public.is_approved_user(auth.uid()));
