-- =====================================================================
-- BAGREFUT - Match events participant-only RLS and safe score summaries
-- =====================================================================

ALTER TABLE public.match_events ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.match_events FORCE ROW LEVEL SECURITY;

REVOKE INSERT, UPDATE, DELETE ON public.match_events FROM authenticated, anon;
REVOKE SELECT ON public.matches FROM authenticated, anon;

CREATE OR REPLACE FUNCTION public.user_participates_in_match(
  _user_id uuid,
  _match_id uuid
)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
  SELECT COALESCE(
    EXISTS (
      SELECT 1
      FROM public.clubs c
      JOIN public.matches m
        ON m.id = _match_id
       AND (m.home_club_id = c.id OR m.away_club_id = c.id)
      WHERE c.owner_id = _user_id
    ),
    false
  )
$$;

REVOKE ALL ON FUNCTION public.user_participates_in_match(uuid, uuid) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.user_participates_in_match(uuid, uuid) FROM anon;
GRANT EXECUTE ON FUNCTION public.user_participates_in_match(uuid, uuid) TO authenticated;

DO $$
DECLARE
  _policy record;
BEGIN
  FOR _policy IN
    SELECT pol.polname
    FROM pg_catalog.pg_policy pol
    JOIN pg_catalog.pg_class cls ON cls.oid = pol.polrelid
    JOIN pg_catalog.pg_namespace nsp ON nsp.oid = cls.relnamespace
    WHERE nsp.nspname = 'public'
      AND cls.relname = 'match_events'
  LOOP
    EXECUTE pg_catalog.format(
      'DROP POLICY IF EXISTS %I ON public.match_events',
      _policy.polname
    );
  END LOOP;
END $$;

CREATE POLICY "match_events_approved_participant_or_admin_read"
ON public.match_events
FOR SELECT
TO authenticated
USING (
  public.is_approved_user(auth.uid())
  AND (
    public.has_role(auth.uid(), 'admin'::public.app_role)
    OR public.user_participates_in_match(auth.uid(), match_events.match_id)
  )
);

DROP FUNCTION IF EXISTS public.list_match_score_summaries(uuid);

CREATE OR REPLACE FUNCTION public.list_match_score_summaries(
  _match_id uuid DEFAULT NULL
)
RETURNS TABLE(
  match_id uuid,
  status public.match_status,
  round_number smallint,
  competition_name text,
  starts_at timestamptz,
  home_club_id uuid,
  home_club_name text,
  home_club_abbreviation text,
  home_club_badge_path text,
  away_club_id uuid,
  away_club_name text,
  away_club_abbreviation text,
  away_club_badge_path text,
  home_goals smallint,
  away_goals smallint,
  final_result text
)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'unauthenticated';
  END IF;

  IF NOT public.is_approved_user(auth.uid()) THEN
    RAISE EXCEPTION 'profile_not_approved';
  END IF;

  RETURN QUERY
  SELECT
    m.id AS match_id,
    m.status,
    r.round_number,
    l.name AS competition_name,
    r.starts_at,
    home.id AS home_club_id,
    home.name AS home_club_name,
    home.abbreviation AS home_club_abbreviation,
    home_badge.asset_path AS home_club_badge_path,
    away.id AS away_club_id,
    away.name AS away_club_name,
    away.abbreviation AS away_club_abbreviation,
    away_badge.asset_path AS away_club_badge_path,
    m.home_goals,
    m.away_goals,
    CASE
      WHEN m.status <> 'finished'::public.match_status THEN 'pending'
      WHEN m.home_goals > m.away_goals THEN 'home_win'
      WHEN m.away_goals > m.home_goals THEN 'away_win'
      ELSE 'draw'
    END AS final_result
  FROM public.matches m
  JOIN public.rounds r ON r.id = m.round_id
  JOIN public.seasons s ON s.id = r.season_id
  JOIN public.leagues l ON l.id = s.league_id
  JOIN public.clubs home ON home.id = m.home_club_id
  JOIN public.clubs away ON away.id = m.away_club_id
  LEFT JOIN public.club_badges home_badge ON home_badge.id = home.badge_id
  LEFT JOIN public.club_badges away_badge ON away_badge.id = away.badge_id
  WHERE _match_id IS NULL OR m.id = _match_id
  ORDER BY r.starts_at DESC, r.round_number DESC, m.created_at DESC;
END
$$;

REVOKE ALL ON FUNCTION public.list_match_score_summaries(uuid) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.list_match_score_summaries(uuid) FROM anon;
GRANT EXECUTE ON FUNCTION public.list_match_score_summaries(uuid) TO authenticated;
