-- =====================================================================
-- BAGREFUT - Season engine, admin setup, standings, finish, and prizes
-- =====================================================================

-- ---------- SEASON SETUP TABLES ----------
CREATE TABLE IF NOT EXISTS public.season_configurations (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  league_id uuid NOT NULL REFERENCES public.leagues(id) ON DELETE RESTRICT,
  season_id uuid UNIQUE REFERENCES public.seasons(id) ON DELETE SET NULL,
  name text NOT NULL,
  start_date date NOT NULL,
  default_match_time time NOT NULL,
  round_interval_days integer NOT NULL DEFAULT 1 CHECK (round_interval_days BETWEEN 1 AND 30),
  timezone text NOT NULL DEFAULT 'America/Belem',
  registration_status text NOT NULL DEFAULT 'open' CHECK (registration_status IN ('open','closed')),
  registration_deadline date,
  status text NOT NULL DEFAULT 'draft' CHECK (status IN ('draft','started','archived')),
  created_by uuid REFERENCES auth.users(id) ON DELETE SET NULL,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT season_configurations_name_len CHECK (char_length(trim(name)) BETWEEN 3 AND 80),
  CONSTRAINT season_configurations_timezone_check CHECK (timezone = 'America/Belem')
);

CREATE UNIQUE INDEX IF NOT EXISTS idx_one_open_season_config_per_league
  ON public.season_configurations(league_id)
  WHERE season_id IS NULL AND status = 'draft';

CREATE TRIGGER trg_season_configurations_updated_at
  BEFORE UPDATE ON public.season_configurations
  FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();

GRANT SELECT ON public.season_configurations TO authenticated;
GRANT ALL ON public.season_configurations TO service_role;
ALTER TABLE public.season_configurations ENABLE ROW LEVEL SECURITY;

CREATE POLICY "season_configurations_admin_read"
ON public.season_configurations
FOR SELECT TO authenticated
USING (public.is_approved_user(auth.uid()) AND public.has_role(auth.uid(), 'admin'));

CREATE TABLE IF NOT EXISTS public.season_config_participants (
  config_id uuid NOT NULL REFERENCES public.season_configurations(id) ON DELETE CASCADE,
  club_id uuid NOT NULL REFERENCES public.clubs(id) ON DELETE RESTRICT,
  sort_order smallint NOT NULL CHECK (sort_order BETWEEN 1 AND 6),
  created_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (config_id, club_id),
  UNIQUE (config_id, sort_order)
);

GRANT SELECT ON public.season_config_participants TO authenticated;
GRANT ALL ON public.season_config_participants TO service_role;
ALTER TABLE public.season_config_participants ENABLE ROW LEVEL SECURITY;

CREATE POLICY "season_config_participants_admin_read"
ON public.season_config_participants
FOR SELECT TO authenticated
USING (public.is_approved_user(auth.uid()) AND public.has_role(auth.uid(), 'admin'));

CREATE TABLE IF NOT EXISTS public.season_prize_config (
  config_id uuid NOT NULL REFERENCES public.season_configurations(id) ON DELETE CASCADE,
  position smallint NOT NULL CHECK (position BETWEEN 1 AND 6),
  amount_cents integer NOT NULL CHECK (amount_cents BETWEEN 0 AND 10000),
  created_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (config_id, position)
);

GRANT SELECT ON public.season_prize_config TO authenticated;
GRANT ALL ON public.season_prize_config TO service_role;
ALTER TABLE public.season_prize_config ENABLE ROW LEVEL SECURITY;

CREATE POLICY "season_prize_config_admin_read"
ON public.season_prize_config
FOR SELECT TO authenticated
USING (public.is_approved_user(auth.uid()) AND public.has_role(auth.uid(), 'admin'));

ALTER TABLE public.seasons
  ADD COLUMN IF NOT EXISTS name text,
  ADD COLUMN IF NOT EXISTS config_id uuid REFERENCES public.season_configurations(id) ON DELETE SET NULL,
  ADD COLUMN IF NOT EXISTS champion_club_id uuid REFERENCES public.clubs(id) ON DELETE SET NULL,
  ADD COLUMN IF NOT EXISTS champion_points integer,
  ADD COLUMN IF NOT EXISTS champion_wins integer,
  ADD COLUMN IF NOT EXISTS champion_goal_difference integer;

CREATE UNIQUE INDEX IF NOT EXISTS idx_one_active_season_per_league
  ON public.seasons(league_id)
  WHERE status = 'active';

CREATE TABLE IF NOT EXISTS public.season_participants (
  season_id uuid NOT NULL REFERENCES public.seasons(id) ON DELETE CASCADE,
  club_id uuid NOT NULL REFERENCES public.clubs(id) ON DELETE RESTRICT,
  sort_order smallint NOT NULL CHECK (sort_order BETWEEN 1 AND 6),
  created_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (season_id, club_id),
  UNIQUE (season_id, sort_order)
);

GRANT SELECT ON public.season_participants TO authenticated;
GRANT ALL ON public.season_participants TO service_role;
ALTER TABLE public.season_participants ENABLE ROW LEVEL SECURITY;

CREATE POLICY "season_participants_approved_read"
ON public.season_participants
FOR SELECT TO authenticated
USING (public.is_approved_user(auth.uid()));

CREATE TABLE IF NOT EXISTS public.season_final_standings (
  season_id uuid NOT NULL REFERENCES public.seasons(id) ON DELETE CASCADE,
  club_id uuid NOT NULL REFERENCES public.clubs(id) ON DELETE RESTRICT,
  position smallint NOT NULL CHECK (position BETWEEN 1 AND 6),
  played integer NOT NULL CHECK (played >= 0),
  points integer NOT NULL CHECK (points >= 0),
  wins integer NOT NULL CHECK (wins >= 0),
  draws integer NOT NULL CHECK (draws >= 0),
  losses integer NOT NULL CHECK (losses >= 0),
  goals_for integer NOT NULL CHECK (goals_for >= 0),
  goals_against integer NOT NULL CHECK (goals_against >= 0),
  goal_difference integer NOT NULL,
  prize_cents integer NOT NULL DEFAULT 0 CHECK (prize_cents >= 0),
  created_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (season_id, club_id),
  UNIQUE (season_id, position)
);

GRANT SELECT ON public.season_final_standings TO authenticated;
GRANT ALL ON public.season_final_standings TO service_role;
ALTER TABLE public.season_final_standings ENABLE ROW LEVEL SECURITY;

CREATE POLICY "season_final_standings_approved_read"
ON public.season_final_standings
FOR SELECT TO authenticated
USING (public.is_approved_user(auth.uid()));

ALTER TABLE public.matches
  ADD COLUMN IF NOT EXISTS scheduled_at timestamptz;

CREATE INDEX IF NOT EXISTS idx_matches_scheduled_at ON public.matches(scheduled_at);

CREATE UNIQUE INDEX IF NOT EXISTS idx_wallet_season_prize_once
  ON public.wallet_transactions(club_id, reference_id)
  WHERE kind = 'season_prize'::public.wallet_transaction_type
    AND reference_table = 'seasons';

-- ---------- INTERNAL HELPERS ----------
CREATE OR REPLACE FUNCTION public._assert_approved_admin()
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  _uid uuid := auth.uid();
BEGIN
  IF _uid IS NULL THEN
    RAISE EXCEPTION 'unauthenticated';
  END IF;
  IF NOT public.is_approved_user(_uid) THEN
    RAISE EXCEPTION 'profile_not_approved';
  END IF;
  IF NOT public.has_role(_uid, 'admin'::public.app_role) THEN
    RAISE EXCEPTION 'forbidden_not_admin';
  END IF;
  RETURN _uid;
END;
$$;

REVOKE ALL ON FUNCTION public._assert_approved_admin() FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public._assert_approved_admin() TO service_role;

CREATE OR REPLACE FUNCTION public._bagreleirao_league_id()
RETURNS uuid
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
  SELECT id FROM public.leagues WHERE slug = 'bagreleirao'
$$;

REVOKE ALL ON FUNCTION public._bagreleirao_league_id() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public._bagreleirao_league_id() TO authenticated, service_role;

CREATE OR REPLACE FUNCTION public._season_club_eligibility(_league_id uuid)
RETURNS TABLE(
  club_id uuid,
  club_name text,
  abbreviation text,
  owner_id uuid,
  owner_username text,
  is_eligible boolean,
  ineligible_reason text
)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
  SELECT
    c.id AS club_id,
    c.name AS club_name,
    c.abbreviation,
    c.owner_id,
    p.username AS owner_username,
    (c.is_active AND p.status = 'approved'::public.user_status) AS is_eligible,
    CASE
      WHEN NOT c.is_active THEN 'club_inactive'
      WHEN p.id IS NULL THEN 'owner_profile_missing'
      WHEN p.status = 'pending'::public.user_status THEN 'owner_pending'
      WHEN p.status = 'blocked'::public.user_status THEN 'owner_blocked'
      WHEN p.status <> 'approved'::public.user_status THEN 'owner_not_approved'
      ELSE NULL
    END AS ineligible_reason
  FROM public.clubs c
  LEFT JOIN public.profiles p ON p.id = c.owner_id
  WHERE c.league_id = _league_id
  ORDER BY c.created_at, c.id
$$;

REVOKE ALL ON FUNCTION public._season_club_eligibility(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public._season_club_eligibility(uuid) TO authenticated, service_role;

CREATE OR REPLACE FUNCTION public._validate_season_config(_config_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  _config public.season_configurations%ROWTYPE;
  _prize_count integer;
BEGIN
  SELECT * INTO _config
  FROM public.season_configurations
  WHERE id = _config_id;

  IF _config.id IS NULL THEN
    RAISE EXCEPTION 'season_config_not_found';
  END IF;
  IF char_length(trim(_config.name)) NOT BETWEEN 3 AND 80 THEN
    RAISE EXCEPTION 'season_name_invalid';
  END IF;
  IF _config.round_interval_days NOT BETWEEN 1 AND 30 THEN
    RAISE EXCEPTION 'season_round_interval_invalid';
  END IF;
  IF _config.timezone <> 'America/Belem' THEN
    RAISE EXCEPTION 'season_timezone_invalid';
  END IF;

  SELECT count(*) INTO _prize_count
  FROM public.season_prize_config
  WHERE config_id = _config_id
    AND position BETWEEN 1 AND 6
    AND amount_cents BETWEEN 0 AND 10000;

  IF _prize_count <> 6 THEN
    RAISE EXCEPTION 'season_prizes_invalid';
  END IF;
END;
$$;

REVOKE ALL ON FUNCTION public._validate_season_config(uuid) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public._validate_season_config(uuid) TO service_role;

-- ---------- READ RPCS ----------
CREATE OR REPLACE FUNCTION public.list_season_club_eligibility(_include_private boolean DEFAULT false)
RETURNS TABLE(
  club_id uuid,
  club_name text,
  abbreviation text,
  owner_id uuid,
  owner_username text,
  is_eligible boolean,
  ineligible_reason text
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  _league_id uuid := public._bagreleirao_league_id();
  _is_admin boolean := public.is_approved_user(auth.uid()) AND public.has_role(auth.uid(), 'admin'::public.app_role);
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'unauthenticated';
  END IF;
  IF NOT public.is_approved_user(auth.uid()) THEN
    RAISE EXCEPTION 'profile_not_approved';
  END IF;

  RETURN QUERY
  SELECT
    e.club_id,
    e.club_name,
    e.abbreviation,
    CASE WHEN _include_private AND _is_admin THEN e.owner_id ELSE NULL END,
    CASE WHEN _include_private AND _is_admin THEN e.owner_username ELSE NULL END,
    e.is_eligible,
    CASE WHEN _include_private AND _is_admin THEN e.ineligible_reason ELSE NULL END
  FROM public._season_club_eligibility(_league_id) e
  WHERE (_include_private AND _is_admin) OR e.is_eligible;
END;
$$;

REVOKE ALL ON FUNCTION public.list_season_club_eligibility(boolean) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.list_season_club_eligibility(boolean) TO authenticated;

CREATE OR REPLACE FUNCTION public.get_current_round_state()
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  _season public.seasons%ROWTYPE;
  _current jsonb;
  _next jsonb;
  _previous jsonb;
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'unauthenticated';
  END IF;
  IF NOT public.is_approved_user(auth.uid()) THEN
    RAISE EXCEPTION 'profile_not_approved';
  END IF;

  SELECT * INTO _season
  FROM public.seasons
  WHERE status = 'active'
  ORDER BY started_at DESC NULLS LAST
  LIMIT 1;

  IF _season.id IS NULL THEN
    RETURN jsonb_build_object(
      'active_season', NULL,
      'current_round', NULL,
      'next_round', NULL,
      'previous_round', NULL
    );
  END IF;

  SELECT jsonb_build_object(
    'round_id', r.id,
    'round_number', r.round_number,
    'status', CASE
      WHEN r.is_processed THEN 'finished'
      WHEN now() < r.starts_at THEN 'scheduled'
      WHEN now() >= r.ends_at THEN 'pending_processing'
      ELSE 'active'
    END,
    'starts_at', r.starts_at,
    'lineup_lock_at', r.lineup_lock_at,
    'ends_at', r.ends_at,
    'match_count', count(m.id),
    'completed_matches', count(m.id) FILTER (WHERE m.status = 'finished'::public.match_status)
  )
  INTO _current
  FROM public.rounds r
  LEFT JOIN public.matches m ON m.round_id = r.id
  WHERE r.season_id = _season.id
    AND (
      now() BETWEEN r.starts_at AND r.ends_at
      OR r.round_number = (
        SELECT r2.round_number
        FROM public.rounds r2
        WHERE r2.season_id = _season.id
        ORDER BY
          CASE
            WHEN now() BETWEEN r2.starts_at AND r2.ends_at THEN 0
            WHEN r2.starts_at > now() THEN 1
            ELSE 2
          END,
          CASE WHEN r2.starts_at > now() THEN r2.starts_at END ASC,
          CASE WHEN r2.starts_at <= now() THEN r2.starts_at END DESC
        LIMIT 1
      )
    )
  GROUP BY r.id;

  SELECT jsonb_build_object(
    'round_id', r.id,
    'round_number', r.round_number,
    'starts_at', r.starts_at,
    'lineup_lock_at', r.lineup_lock_at,
    'match_count', count(m.id),
    'completed_matches', count(m.id) FILTER (WHERE m.status = 'finished'::public.match_status)
  )
  INTO _next
  FROM public.rounds r
  LEFT JOIN public.matches m ON m.round_id = r.id
  WHERE r.season_id = _season.id
    AND r.starts_at > now()
  GROUP BY r.id
  ORDER BY r.starts_at
  LIMIT 1;

  SELECT jsonb_build_object(
    'round_id', r.id,
    'round_number', r.round_number,
    'starts_at', r.starts_at,
    'lineup_lock_at', r.lineup_lock_at,
    'match_count', count(m.id),
    'completed_matches', count(m.id) FILTER (WHERE m.status = 'finished'::public.match_status)
  )
  INTO _previous
  FROM public.rounds r
  LEFT JOIN public.matches m ON m.round_id = r.id
  WHERE r.season_id = _season.id
    AND r.ends_at < now()
  GROUP BY r.id
  ORDER BY r.starts_at DESC
  LIMIT 1;

  RETURN jsonb_build_object(
    'active_season', jsonb_build_object(
      'season_id', _season.id,
      'name', coalesce(_season.name, 'Temporada ' || _season.season_number::text),
      'status', _season.status,
      'started_at', _season.started_at
    ),
    'current_round', _current,
    'next_round', _next,
    'previous_round', _previous
  );
END;
$$;

REVOKE ALL ON FUNCTION public.get_current_round_state() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.get_current_round_state() TO authenticated;

CREATE OR REPLACE FUNCTION public.get_season_operational_state()
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  _league_id uuid := public._bagreleirao_league_id();
  _eligible_count integer;
  _active public.seasons%ROWTYPE;
  _last_finished public.seasons%ROWTYPE;
  _round_state jsonb;
  _status text;
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'unauthenticated';
  END IF;
  IF NOT public.is_approved_user(auth.uid()) THEN
    RAISE EXCEPTION 'profile_not_approved';
  END IF;

  SELECT count(*) INTO _eligible_count
  FROM public._season_club_eligibility(_league_id)
  WHERE is_eligible;

  SELECT * INTO _active
  FROM public.seasons
  WHERE league_id = _league_id
    AND status = 'active'
  ORDER BY started_at DESC NULLS LAST
  LIMIT 1;

  SELECT * INTO _last_finished
  FROM public.seasons
  WHERE league_id = _league_id
    AND status = 'finished'
  ORDER BY finished_at DESC NULLS LAST
  LIMIT 1;

  IF _active.id IS NOT NULL THEN
    _status := 'active';
    _round_state := public.get_current_round_state();
  ELSIF _eligible_count < 6 THEN
    _status := 'waiting_for_clubs';
    _round_state := jsonb_build_object('active_season', NULL, 'current_round', NULL, 'next_round', NULL, 'previous_round', NULL);
  ELSE
    _status := 'ready_to_start';
    _round_state := jsonb_build_object('active_season', NULL, 'current_round', NULL, 'next_round', NULL, 'previous_round', NULL);
  END IF;

  RETURN jsonb_build_object(
    'operational_status', _status,
    'eligible_count', _eligible_count,
    'required_count', 6,
    'missing_count', greatest(0, 6 - _eligible_count),
    'active_season', _round_state->'active_season',
    'current_round', _round_state->'current_round',
    'next_round', _round_state->'next_round',
    'previous_round', _round_state->'previous_round',
    'last_finished_season', CASE
      WHEN _last_finished.id IS NULL THEN NULL
      ELSE jsonb_build_object(
        'season_id', _last_finished.id,
        'name', coalesce(_last_finished.name, 'Temporada ' || _last_finished.season_number::text),
        'status', _last_finished.status,
        'champion_club_id', _last_finished.champion_club_id,
        'finished_at', _last_finished.finished_at
      )
    END
  );
END;
$$;

REVOKE ALL ON FUNCTION public.get_season_operational_state() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.get_season_operational_state() TO authenticated;

CREATE OR REPLACE FUNCTION public.get_season_standings(_season_id uuid DEFAULT NULL)
RETURNS TABLE(
  "position" integer,
  club_id uuid,
  club_name text,
  abbreviation text,
  played integer,
  points integer,
  wins integer,
  draws integer,
  losses integer,
  goals_for integer,
  goals_against integer,
  goal_difference integer
)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
  WITH target_season AS (
    SELECT s.id
    FROM public.seasons s
    WHERE s.id = COALESCE(
      _season_id,
      (SELECT active.id FROM public.seasons active WHERE active.status = 'active' ORDER BY active.started_at DESC NULLS LAST LIMIT 1),
      (SELECT latest.id FROM public.seasons latest ORDER BY latest.started_at DESC NULLS LAST, latest.created_at DESC LIMIT 1)
    )
    LIMIT 1
  ),
  results AS (
    SELECT
      m.home_club_id AS club_id,
      m.home_goals AS gf,
      m.away_goals AS ga,
      CASE WHEN m.home_goals > m.away_goals THEN 1 ELSE 0 END AS win,
      CASE WHEN m.home_goals = m.away_goals THEN 1 ELSE 0 END AS draw,
      CASE WHEN m.home_goals < m.away_goals THEN 1 ELSE 0 END AS loss
    FROM public.matches m
    JOIN public.rounds r ON r.id = m.round_id
    JOIN target_season ts ON ts.id = r.season_id
    WHERE m.status = 'finished'::public.match_status
    UNION ALL
    SELECT
      m.away_club_id AS club_id,
      m.away_goals AS gf,
      m.home_goals AS ga,
      CASE WHEN m.away_goals > m.home_goals THEN 1 ELSE 0 END AS win,
      CASE WHEN m.away_goals = m.home_goals THEN 1 ELSE 0 END AS draw,
      CASE WHEN m.away_goals < m.home_goals THEN 1 ELSE 0 END AS loss
    FROM public.matches m
    JOIN public.rounds r ON r.id = m.round_id
    JOIN target_season ts ON ts.id = r.season_id
    WHERE m.status = 'finished'::public.match_status
  ),
  aggregated AS (
    SELECT
      sp.club_id,
      count(r.club_id)::integer AS played,
      coalesce(sum(r.win), 0)::integer AS wins,
      coalesce(sum(r.draw), 0)::integer AS draws,
      coalesce(sum(r.loss), 0)::integer AS losses,
      coalesce(sum(r.gf), 0)::integer AS goals_for,
      coalesce(sum(r.ga), 0)::integer AS goals_against
    FROM public.season_participants sp
    JOIN target_season ts ON ts.id = sp.season_id
    LEFT JOIN results r ON r.club_id = sp.club_id
    GROUP BY sp.club_id
  )
  SELECT
    row_number() OVER (
      ORDER BY
        (a.wins * 3 + a.draws) DESC,
        a.wins DESC,
        (a.goals_for - a.goals_against) DESC,
        a.goals_for DESC,
        c.name ASC,
        c.id ASC
    )::integer AS "position",
    c.id AS club_id,
    c.name AS club_name,
    c.abbreviation,
    a.played,
    (a.wins * 3 + a.draws)::integer AS points,
    a.wins,
    a.draws,
    a.losses,
    a.goals_for,
    a.goals_against,
    (a.goals_for - a.goals_against)::integer AS goal_difference
  FROM aggregated a
  JOIN public.clubs c ON c.id = a.club_id
  ORDER BY 1;
$$;

REVOKE ALL ON FUNCTION public.get_season_standings(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.get_season_standings(uuid) TO authenticated;

CREATE OR REPLACE FUNCTION public.get_season_history()
RETURNS jsonb
LANGUAGE plpgsql
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

  RETURN (
    SELECT coalesce(jsonb_agg(
      jsonb_build_object(
        'season_id', s.id,
        'name', coalesce(s.name, 'Temporada ' || s.season_number::text),
        'status', s.status,
        'started_at', s.started_at,
        'finished_at', s.finished_at,
        'champion_club_id', s.champion_club_id,
        'champion_club_name', c.name,
        'standings', coalesce((
          SELECT jsonb_agg(to_jsonb(fs) ORDER BY fs.position)
          FROM public.season_final_standings fs
          WHERE fs.season_id = s.id
        ), '[]'::jsonb)
      )
      ORDER BY s.started_at DESC NULLS LAST, s.created_at DESC
    ), '[]'::jsonb)
    FROM public.seasons s
    LEFT JOIN public.clubs c ON c.id = s.champion_club_id
    WHERE s.status = 'finished'
  );
END;
$$;

REVOKE ALL ON FUNCTION public.get_season_history() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.get_season_history() TO authenticated;

-- ---------- ADMIN RPCS ----------
CREATE OR REPLACE FUNCTION public.admin_upsert_season_setup(_config jsonb)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  _admin_id uuid := public._assert_approved_admin();
  _league_id uuid := public._bagreleirao_league_id();
  _config_id uuid;
  _name text := trim(_config->>'name');
  _start_date date;
  _match_time time;
  _round_interval integer;
  _timezone text := coalesce(_config->>'timezone', 'America/Belem');
  _registration_status text := coalesce(_config->>'registration_status', 'open');
  _registration_deadline date;
  _prizes jsonb := _config->'prizes_cents';
  _idx integer;
  _eligible_count integer;
BEGIN
  IF _league_id IS NULL THEN
    RAISE EXCEPTION 'league_missing';
  END IF;

  IF _name IS NULL OR char_length(_name) NOT BETWEEN 3 AND 80 THEN
    RAISE EXCEPTION 'season_name_invalid';
  END IF;
  BEGIN
    _start_date := (_config->>'start_date')::date;
  EXCEPTION WHEN OTHERS THEN
    RAISE EXCEPTION 'season_start_date_invalid';
  END;
  BEGIN
    _match_time := (_config->>'default_match_time')::time;
  EXCEPTION WHEN OTHERS THEN
    RAISE EXCEPTION 'season_match_time_invalid';
  END;
  _round_interval := (_config->>'round_interval_days')::integer;
  IF _round_interval NOT BETWEEN 1 AND 30 THEN
    RAISE EXCEPTION 'season_round_interval_invalid';
  END IF;
  IF _timezone <> 'America/Belem' THEN
    RAISE EXCEPTION 'season_timezone_invalid';
  END IF;
  IF _registration_status NOT IN ('open','closed') THEN
    RAISE EXCEPTION 'season_registration_status_invalid';
  END IF;
  IF _config ? 'registration_deadline' AND _config->>'registration_deadline' IS NOT NULL THEN
    _registration_deadline := (_config->>'registration_deadline')::date;
  END IF;
  IF jsonb_typeof(_prizes) <> 'array' OR jsonb_array_length(_prizes) <> 6 THEN
    RAISE EXCEPTION 'season_prizes_invalid';
  END IF;

  SELECT id INTO _config_id
  FROM public.season_configurations
  WHERE league_id = _league_id
    AND season_id IS NULL
    AND status = 'draft'
  ORDER BY created_at DESC
  LIMIT 1
  FOR UPDATE;

  IF _config_id IS NULL THEN
    INSERT INTO public.season_configurations (
      league_id,
      name,
      start_date,
      default_match_time,
      round_interval_days,
      timezone,
      registration_status,
      registration_deadline,
      created_by
    )
    VALUES (
      _league_id,
      _name,
      _start_date,
      _match_time,
      _round_interval,
      _timezone,
      _registration_status,
      _registration_deadline,
      _admin_id
    )
    RETURNING id INTO _config_id;
  ELSE
    UPDATE public.season_configurations
    SET name = _name,
        start_date = _start_date,
        default_match_time = _match_time,
        round_interval_days = _round_interval,
        timezone = _timezone,
        registration_status = _registration_status,
        registration_deadline = _registration_deadline,
        created_by = coalesce(created_by, _admin_id)
    WHERE id = _config_id;
  END IF;

  DELETE FROM public.season_prize_config WHERE config_id = _config_id;
  FOR _idx IN 0..5 LOOP
    IF ((_prizes->_idx)::text)::integer < 0 OR ((_prizes->_idx)::text)::integer > 10000 THEN
      RAISE EXCEPTION 'season_prizes_invalid';
    END IF;
    INSERT INTO public.season_prize_config(config_id, position, amount_cents)
    VALUES (_config_id, (_idx + 1)::smallint, ((_prizes->_idx)::text)::integer);
  END LOOP;

  SELECT count(*) INTO _eligible_count
  FROM public._season_club_eligibility(_league_id)
  WHERE is_eligible;

  IF _eligible_count = 6
     AND NOT EXISTS (SELECT 1 FROM public.season_config_participants WHERE config_id = _config_id) THEN
    INSERT INTO public.season_config_participants(config_id, club_id, sort_order)
    SELECT _config_id, e.club_id, row_number() OVER (ORDER BY c.created_at, c.id)::smallint
    FROM public._season_club_eligibility(_league_id) e
    JOIN public.clubs c ON c.id = e.club_id
    WHERE e.is_eligible
    ORDER BY c.created_at, c.id;
  END IF;

  PERFORM public._validate_season_config(_config_id);

  RETURN jsonb_build_object(
    'config_id', _config_id,
    'eligible_count', _eligible_count,
    'required_count', 6,
    'missing_count', greatest(0, 6 - _eligible_count)
  );
END;
$$;

REVOKE ALL ON FUNCTION public.admin_upsert_season_setup(jsonb) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.admin_upsert_season_setup(jsonb) TO authenticated;

CREATE OR REPLACE FUNCTION public.admin_set_season_participants(_config_id uuid, _club_ids uuid[])
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  _config public.season_configurations%ROWTYPE;
  _club_id uuid;
  _idx integer := 1;
  _distinct_count integer;
BEGIN
  PERFORM public._assert_approved_admin();

  SELECT * INTO _config
  FROM public.season_configurations
  WHERE id = _config_id
  FOR UPDATE;

  IF _config.id IS NULL THEN
    RAISE EXCEPTION 'season_config_not_found';
  END IF;
  IF _config.season_id IS NOT NULL OR _config.status <> 'draft' THEN
    RAISE EXCEPTION 'season_config_locked';
  END IF;

  SELECT count(DISTINCT selected.club_id) INTO _distinct_count
  FROM unnest(_club_ids) AS selected(club_id);

  IF _distinct_count <> coalesce(array_length(_club_ids, 1), 0) THEN
    RAISE EXCEPTION 'season_selection_has_duplicates';
  END IF;
  IF coalesce(array_length(_club_ids, 1), 0) > 6 THEN
    RAISE EXCEPTION 'season_selection_requires_exactly_6';
  END IF;
  IF EXISTS (
    SELECT 1
    FROM unnest(_club_ids) AS selected(club_id)
    LEFT JOIN public._season_club_eligibility(_config.league_id) e
      ON e.club_id = selected.club_id
     AND e.is_eligible
    WHERE e.club_id IS NULL
  ) THEN
    RAISE EXCEPTION 'season_selected_club_ineligible';
  END IF;

  DELETE FROM public.season_config_participants WHERE config_id = _config_id;
  FOREACH _club_id IN ARRAY _club_ids LOOP
    INSERT INTO public.season_config_participants(config_id, club_id, sort_order)
    VALUES (_config_id, _club_id, _idx::smallint);
    _idx := _idx + 1;
  END LOOP;

  RETURN jsonb_build_object(
    'config_id', _config_id,
    'selected_count', coalesce(array_length(_club_ids, 1), 0)
  );
END;
$$;

REVOKE ALL ON FUNCTION public.admin_set_season_participants(uuid, uuid[]) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.admin_set_season_participants(uuid, uuid[]) TO authenticated;

CREATE OR REPLACE FUNCTION public.admin_get_season_setup()
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  _league_id uuid := public._bagreleirao_league_id();
  _config public.season_configurations%ROWTYPE;
BEGIN
  PERFORM public._assert_approved_admin();

  SELECT * INTO _config
  FROM public.season_configurations
  WHERE league_id = _league_id
    AND season_id IS NULL
    AND status = 'draft'
  ORDER BY created_at DESC
  LIMIT 1;

  RETURN jsonb_build_object(
    'operational_state', public.get_season_operational_state(),
    'config', CASE
      WHEN _config.id IS NULL THEN NULL
      ELSE to_jsonb(_config)
    END,
    'eligibility', (
      SELECT coalesce(jsonb_agg(to_jsonb(e) ORDER BY e.club_name, e.club_id), '[]'::jsonb)
      FROM public.list_season_club_eligibility(true) e
    ),
    'selected_club_ids', CASE
      WHEN _config.id IS NULL THEN '[]'::jsonb
      ELSE (
        SELECT coalesce(jsonb_agg(p.club_id ORDER BY p.sort_order), '[]'::jsonb)
        FROM public.season_config_participants p
        WHERE p.config_id = _config.id
      )
    END,
    'prizes', CASE
      WHEN _config.id IS NULL THEN '[]'::jsonb
      ELSE (
        SELECT coalesce(jsonb_agg(sp.amount_cents ORDER BY sp.position), '[]'::jsonb)
        FROM public.season_prize_config sp
        WHERE sp.config_id = _config.id
      )
    END
  );
END;
$$;

REVOKE ALL ON FUNCTION public.admin_get_season_setup() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.admin_get_season_setup() TO authenticated;

CREATE OR REPLACE FUNCTION public.season_start(_config_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  _admin_id uuid := public._assert_approved_admin();
  _config public.season_configurations%ROWTYPE;
  _season_id uuid;
  _season_number integer;
  _selected_count integer;
  _round_start timestamptz;
  _round_id uuid;
  _round_number integer;
  _active_season_id uuid;
  _match_count integer;
BEGIN
  SELECT * INTO _config
  FROM public.season_configurations
  WHERE id = _config_id
  FOR UPDATE;

  IF _config.id IS NULL THEN
    RAISE EXCEPTION 'season_config_not_found';
  END IF;

  IF _config.season_id IS NOT NULL THEN
    SELECT count(*) INTO _match_count
    FROM public.matches m
    JOIN public.rounds r ON r.id = m.round_id
    WHERE r.season_id = _config.season_id;

    RETURN jsonb_build_object(
      'season_id', _config.season_id,
      'round_count', (SELECT count(*) FROM public.rounds WHERE season_id = _config.season_id),
      'match_count', _match_count,
      'idempotent', true
    );
  END IF;

  PERFORM public._validate_season_config(_config_id);

  SELECT count(*) INTO _selected_count
  FROM public.season_config_participants
  WHERE config_id = _config_id;

  IF _selected_count <> 6 THEN
    RAISE EXCEPTION 'season_selection_requires_exactly_6';
  END IF;

  IF EXISTS (
    SELECT 1
    FROM public.season_config_participants p
    LEFT JOIN public._season_club_eligibility(_config.league_id) e
      ON e.club_id = p.club_id
     AND e.is_eligible
    WHERE p.config_id = _config_id
      AND e.club_id IS NULL
  ) THEN
    RAISE EXCEPTION 'season_selected_club_ineligible';
  END IF;

  SELECT id INTO _active_season_id
  FROM public.seasons
  WHERE league_id = _config.league_id
    AND status = 'active'
  LIMIT 1
  FOR UPDATE;

  IF _active_season_id IS NOT NULL THEN
    RAISE EXCEPTION 'active_season_exists';
  END IF;

  SELECT coalesce(max(season_number), 0) + 1 INTO _season_number
  FROM public.seasons
  WHERE league_id = _config.league_id;

  INSERT INTO public.seasons (league_id, season_number, status, started_at, name, config_id)
  VALUES (_config.league_id, _season_number, 'active', now(), _config.name, _config.id)
  RETURNING id INTO _season_id;

  INSERT INTO public.season_participants(season_id, club_id, sort_order)
  SELECT _season_id, club_id, sort_order
  FROM public.season_config_participants
  WHERE config_id = _config_id
  ORDER BY sort_order;

  FOR _round_number IN 1..10 LOOP
    _round_start := ((_config.start_date::text || ' ' || _config.default_match_time::text)::timestamp AT TIME ZONE _config.timezone)
      + ((_round_number - 1) * _config.round_interval_days) * interval '1 day';

    INSERT INTO public.rounds (
      season_id,
      round_number,
      lineup_lock_at,
      starts_at,
      ends_at,
      is_processed
    )
    VALUES (
      _season_id,
      _round_number,
      _round_start - interval '5 minutes',
      _round_start,
      _round_start + interval '10 minutes',
      false
    )
    RETURNING id INTO _round_id;

    INSERT INTO public.matches(round_id, home_club_id, away_club_id, status, scheduled_at)
    SELECT
      _round_id,
      home_participant.club_id,
      away_participant.club_id,
      'scheduled'::public.match_status,
      _round_start
    FROM (
      VALUES
        (1, 1, 6), (1, 2, 5), (1, 3, 4),
        (2, 6, 4), (2, 5, 3), (2, 1, 2),
        (3, 2, 6), (3, 3, 1), (3, 4, 5),
        (4, 6, 5), (4, 1, 4), (4, 2, 3),
        (5, 3, 6), (5, 4, 2), (5, 5, 1),
        (6, 6, 1), (6, 5, 2), (6, 4, 3),
        (7, 4, 6), (7, 3, 5), (7, 2, 1),
        (8, 6, 2), (8, 1, 3), (8, 5, 4),
        (9, 5, 6), (9, 4, 1), (9, 3, 2),
        (10, 6, 3), (10, 2, 4), (10, 1, 5)
    ) AS fixture(round_number, home_order, away_order)
    JOIN public.season_participants home_participant
      ON home_participant.season_id = _season_id
     AND home_participant.sort_order = fixture.home_order
    JOIN public.season_participants away_participant
      ON away_participant.season_id = _season_id
     AND away_participant.sort_order = fixture.away_order
    WHERE fixture.round_number = _round_number;
  END LOOP;

  UPDATE public.season_configurations
  SET season_id = _season_id,
      status = 'started'
  WHERE id = _config_id;

  UPDATE public.leagues
  SET status = 'active'::public.league_status
  WHERE id = _config.league_id;

  INSERT INTO public.admin_audit_logs(admin_id, action, target_table, target_id, payload)
  VALUES (
    _admin_id,
    'season_start',
    'seasons',
    _season_id,
    jsonb_build_object('config_id', _config_id, 'season_number', _season_number)
  );

  RETURN jsonb_build_object(
    'season_id', _season_id,
    'season_number', _season_number,
    'round_count', (SELECT count(*) FROM public.rounds WHERE season_id = _season_id),
    'match_count', (
      SELECT count(*)
      FROM public.matches m
      JOIN public.rounds r ON r.id = m.round_id
      WHERE r.season_id = _season_id
    ),
    'idempotent', false
  );
END;
$$;

REVOKE ALL ON FUNCTION public.season_start(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.season_start(uuid) TO authenticated;

CREATE OR REPLACE FUNCTION public.season_finish(_season_id uuid DEFAULT NULL)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  _admin_id uuid := public._assert_approved_admin();
  _season public.seasons%ROWTYPE;
  _match_total integer;
  _pending_total integer;
  _standing record;
  _champion record;
  _prize integer;
  _balance integer;
BEGIN
  SELECT * INTO _season
  FROM public.seasons
  WHERE id = COALESCE(
      _season_id,
      (SELECT active.id FROM public.seasons active WHERE active.status = 'active' ORDER BY active.started_at DESC NULLS LAST LIMIT 1)
    )
  FOR UPDATE;

  IF _season.id IS NULL OR _season.status <> 'active' THEN
    RAISE EXCEPTION 'season_not_active';
  END IF;

  SELECT
    count(*),
    count(*) FILTER (WHERE m.status <> 'finished'::public.match_status)
  INTO _match_total, _pending_total
  FROM public.matches m
  JOIN public.rounds r ON r.id = m.round_id
  WHERE r.season_id = _season.id;

  IF _match_total <> 30 OR _pending_total <> 0 THEN
    RAISE EXCEPTION 'season_has_pending_matches';
  END IF;

  INSERT INTO public.season_final_standings (
    season_id,
    club_id,
    position,
    played,
    points,
    wins,
    draws,
    losses,
    goals_for,
    goals_against,
    goal_difference,
    prize_cents
  )
  SELECT
    _season.id,
    s.club_id,
    s.position,
    s.played,
    s.points,
    s.wins,
    s.draws,
    s.losses,
    s.goals_for,
    s.goals_against,
    s.goal_difference,
    coalesce(pc.amount_cents, 0)
  FROM public.get_season_standings(_season.id) s
  LEFT JOIN public.season_prize_config pc
    ON pc.config_id = _season.config_id
   AND pc.position = s.position
  ON CONFLICT (season_id, club_id) DO NOTHING;

  SELECT * INTO _champion
  FROM public.season_final_standings
  WHERE season_id = _season.id
    AND position = 1;

  IF _champion.club_id IS NULL THEN
    RAISE EXCEPTION 'season_standings_unavailable';
  END IF;

  FOR _standing IN
    SELECT *
    FROM public.season_final_standings
    WHERE season_id = _season.id
    ORDER BY position
  LOOP
    IF EXISTS (
      SELECT 1
      FROM public.wallet_transactions wt
      WHERE wt.club_id = _standing.club_id
        AND wt.kind = 'season_prize'::public.wallet_transaction_type
        AND wt.reference_table = 'seasons'
        AND wt.reference_id = _season.id
    ) THEN
      RAISE EXCEPTION 'season_prize_already_credited';
    END IF;

    _prize := _standing.prize_cents;
    IF _prize > 0 THEN
      PERFORM public._credit_wallet(
        _standing.club_id,
        _prize,
        'season_prize'::public.wallet_transaction_type,
        'seasons',
        _season.id,
        'premiacao final posicao ' || _standing.position::text
      );
    ELSE
      SELECT balance_cents INTO _balance
      FROM public.clubs
      WHERE id = _standing.club_id;

      INSERT INTO public.wallet_transactions(
        club_id,
        amount_cents,
        balance_after_cents,
        kind,
        reference_table,
        reference_id,
        memo
      )
      VALUES (
        _standing.club_id,
        0,
        _balance,
        'season_prize'::public.wallet_transaction_type,
        'seasons',
        _season.id,
        'premiacao final posicao ' || _standing.position::text
      );
    END IF;
  END LOOP;

  UPDATE public.seasons
  SET status = 'finished',
      finished_at = now(),
      champion_club_id = _champion.club_id,
      champion_points = _champion.points,
      champion_wins = _champion.wins,
      champion_goal_difference = _champion.goal_difference
  WHERE id = _season.id;

  UPDATE public.leagues
  SET status = 'finished'::public.league_status
  WHERE id = _season.league_id;

  INSERT INTO public.admin_audit_logs(admin_id, action, target_table, target_id, payload)
  VALUES (
    _admin_id,
    'season_finish',
    'seasons',
    _season.id,
    jsonb_build_object(
      'champion_club_id', _champion.club_id,
      'champion_points', _champion.points
    )
  );

  RETURN jsonb_build_object(
    'season_id', _season.id,
    'champion_club_id', _champion.club_id,
    'champion_points', _champion.points,
    'champion_wins', _champion.wins,
    'champion_goal_difference', _champion.goal_difference
  );
END;
$$;

REVOKE ALL ON FUNCTION public.season_finish(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.season_finish(uuid) TO authenticated;
