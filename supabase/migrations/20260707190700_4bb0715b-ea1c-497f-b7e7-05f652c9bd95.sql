
-- =====================================================================
-- BAGREFUT - Migration 001: enums, roles, profiles, leagues, badges
-- =====================================================================

CREATE TYPE public.app_role AS ENUM ('admin', 'user');
CREATE TYPE public.user_status AS ENUM ('pending', 'approved', 'blocked');
CREATE TYPE public.league_status AS ENUM ('setup', 'active', 'finished');
CREATE TYPE public.player_position AS ENUM ('GK', 'DEF', 'MID', 'ATA');
CREATE TYPE public.player_rarity AS ENUM ('peba', 'paia', 'pika');
CREATE TYPE public.player_sector AS ENUM (
  'centro','cidade_nova','promissao','jaderlandia','uraim','jardim',
  'flamboyant','angelim','camboata','buriti','laercio','bela_vista',
  'nagibao','ipixuna','caipe','paulo_sexto','morada_do_sol','morada_do_vento',
  'nova_conquista'
);
CREATE TYPE public.play_style AS ENUM ('balanced', 'offensive', 'defensive');
CREATE TYPE public.formation AS ENUM ('1-2-1-1', '1-1-2-1', '1-1-1-2', '0-2-2-1');
CREATE TYPE public.match_status AS ENUM ('scheduled', 'live', 'finished', 'cancelled');
CREATE TYPE public.match_event_type AS ENUM (
  'match_started','pressure','chance','shot','save','goal','halftime','match_finished'
);
CREATE TYPE public.market_listing_status AS ENUM ('open', 'sold', 'cancelled', 'expired');
CREATE TYPE public.transfer_offer_status AS ENUM ('pending', 'accepted', 'rejected', 'cancelled', 'expired');
CREATE TYPE public.wallet_transaction_type AS ENUM (
  'initial_credit','match_reward','season_prize','market_sale','market_purchase',
  'system_sale','system_purchase','training_cost','transfer_cash','admin_adjustment'
);
CREATE TYPE public.notification_type AS ENUM (
  'account_approved','round_today','round_soon','round_result',
  'offer_received','offer_accepted','offer_rejected','card_sold'
);

CREATE OR REPLACE FUNCTION public.set_updated_at()
RETURNS TRIGGER LANGUAGE plpgsql SET search_path = '' AS $$
BEGIN NEW.updated_at = now(); RETURN NEW; END;
$$;

-- ---------- USER_ROLES ----------
CREATE TABLE public.user_roles (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  role public.app_role NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE (user_id, role)
);
CREATE INDEX idx_user_roles_user ON public.user_roles(user_id);
GRANT SELECT ON public.user_roles TO authenticated;
GRANT ALL ON public.user_roles TO service_role;
ALTER TABLE public.user_roles ENABLE ROW LEVEL SECURITY;

CREATE OR REPLACE FUNCTION public.has_role(_user_id uuid, _role public.app_role)
RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path = '' AS $$
  SELECT EXISTS (SELECT 1 FROM public.user_roles WHERE user_id = _user_id AND role = _role)
$$;
REVOKE ALL ON FUNCTION public.has_role(uuid, public.app_role) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.has_role(uuid, public.app_role) TO authenticated, service_role;

CREATE POLICY "user_roles_self_select" ON public.user_roles
  FOR SELECT TO authenticated
  USING (auth.uid() = user_id OR public.has_role(auth.uid(), 'admin'));

-- ---------- PROFILES ----------
CREATE TABLE public.profiles (
  id uuid PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
  username text NOT NULL,
  status public.user_status NOT NULL DEFAULT 'pending',
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT profiles_username_format CHECK (username ~ '^[A-Za-z0-9]{3,16}$')
);
CREATE UNIQUE INDEX idx_profiles_username_lower ON public.profiles (LOWER(username));
CREATE INDEX idx_profiles_status ON public.profiles(status);

GRANT SELECT, UPDATE ON public.profiles TO authenticated;
GRANT ALL ON public.profiles TO service_role;
ALTER TABLE public.profiles ENABLE ROW LEVEL SECURITY;

CREATE TRIGGER trg_profiles_updated_at
  BEFORE UPDATE ON public.profiles
  FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();

CREATE POLICY "profiles_self_select" ON public.profiles
  FOR SELECT TO authenticated
  USING (auth.uid() = id OR public.has_role(auth.uid(), 'admin'));

-- Only admins can update profiles directly; regular users' state changes go through RPCs.
CREATE POLICY "profiles_admin_update" ON public.profiles
  FOR UPDATE TO authenticated
  USING (public.has_role(auth.uid(), 'admin'))
  WITH CHECK (public.has_role(auth.uid(), 'admin'));

-- Auto-create profile on signup; username comes from raw_user_meta_data.
CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS TRIGGER LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $$
DECLARE _username text;
BEGIN
  _username := NEW.raw_user_meta_data ->> 'username';
  IF _username IS NULL OR _username !~ '^[A-Za-z0-9]{3,16}$' THEN
    RAISE EXCEPTION 'invalid_username';
  END IF;
  INSERT INTO public.profiles (id, username, status) VALUES (NEW.id, _username, 'pending');
  RETURN NEW;
END;
$$;
REVOKE ALL ON FUNCTION public.handle_new_user() FROM PUBLIC;

CREATE TRIGGER on_auth_user_created
  AFTER INSERT ON auth.users
  FOR EACH ROW EXECUTE FUNCTION public.handle_new_user();

-- ---------- LEAGUES ----------
CREATE TABLE public.leagues (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  slug text NOT NULL UNIQUE,
  name text NOT NULL,
  max_clubs int NOT NULL DEFAULT 6 CHECK (max_clubs > 0),
  status public.league_status NOT NULL DEFAULT 'setup',
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);
GRANT SELECT ON public.leagues TO authenticated;
GRANT ALL ON public.leagues TO service_role;
ALTER TABLE public.leagues ENABLE ROW LEVEL SECURITY;

CREATE TRIGGER trg_leagues_updated_at
  BEFORE UPDATE ON public.leagues
  FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();

CREATE POLICY "leagues_authenticated_read" ON public.leagues
  FOR SELECT TO authenticated USING (true);

INSERT INTO public.leagues (slug, name, max_clubs, status)
VALUES ('bagreleirao', 'Bagreleirão', 6, 'setup')
ON CONFLICT (slug) DO NOTHING;

-- ---------- CLUB BADGES ----------
CREATE TABLE public.club_badges (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  code text NOT NULL UNIQUE,
  label text NOT NULL,
  asset_path text NOT NULL,
  sort_order int NOT NULL DEFAULT 0,
  is_active boolean NOT NULL DEFAULT true,
  created_at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX idx_club_badges_active ON public.club_badges(is_active, sort_order);
GRANT SELECT ON public.club_badges TO authenticated;
GRANT ALL ON public.club_badges TO service_role;
ALTER TABLE public.club_badges ENABLE ROW LEVEL SECURITY;

CREATE POLICY "club_badges_authenticated_read" ON public.club_badges
  FOR SELECT TO authenticated USING (is_active);

INSERT INTO public.club_badges (code, label, asset_path, sort_order)
SELECT
  'badge-' || lpad(i::text, 2, '0'),
  'Escudo ' || lpad(i::text, 2, '0'),
  '/badges/badge-' || lpad(i::text, 2, '0') || '.png',
  i
FROM generate_series(1, 21) AS g(i)
ON CONFLICT (code) DO NOTHING;
