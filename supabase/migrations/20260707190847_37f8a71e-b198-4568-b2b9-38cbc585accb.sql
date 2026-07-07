
-- =====================================================================
-- BAGREFUT - Migration 003: clubs, players, packs, wallet + core RPCs
-- =====================================================================

-- ---------- CLUBS ----------
CREATE TABLE public.clubs (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  league_id uuid NOT NULL REFERENCES public.leagues(id) ON DELETE RESTRICT,
  owner_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE RESTRICT,
  name text NOT NULL,
  abbreviation text NOT NULL,
  badge_id uuid NOT NULL REFERENCES public.club_badges(id) ON DELETE RESTRICT,
  balance_cents integer NOT NULL DEFAULT 0,
  is_active boolean NOT NULL DEFAULT true,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT clubs_name_format CHECK (char_length(name) BETWEEN 3 AND 24),
  CONSTRAINT clubs_abbr_format CHECK (abbreviation ~ '^[A-Z]{2,4}$'),
  CONSTRAINT clubs_balance_nonneg CHECK (balance_cents >= 0),
  CONSTRAINT clubs_balance_cap CHECK (balance_cents <= 10000),
  CONSTRAINT clubs_one_per_owner UNIQUE (owner_id)
);
CREATE UNIQUE INDEX idx_clubs_name_unique_per_league ON public.clubs (league_id, LOWER(name));
CREATE UNIQUE INDEX idx_clubs_abbr_unique_per_league ON public.clubs (league_id, abbreviation);
CREATE INDEX idx_clubs_league ON public.clubs(league_id);
CREATE INDEX idx_clubs_owner ON public.clubs(owner_id);

GRANT SELECT ON public.clubs TO authenticated;
GRANT ALL ON public.clubs TO service_role;
ALTER TABLE public.clubs ENABLE ROW LEVEL SECURITY;

CREATE TRIGGER trg_clubs_updated_at
  BEFORE UPDATE ON public.clubs FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();

-- All authenticated users can read all clubs (leaderboard / market context);
-- writes only via SECURITY DEFINER RPCs. No direct INSERT/UPDATE/DELETE policy.
CREATE POLICY "clubs_authenticated_read" ON public.clubs
  FOR SELECT TO authenticated USING (true);

-- ---------- PLAYERS (global catalog) ----------
CREATE TABLE public.players (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  code text NOT NULL UNIQUE,
  name text NOT NULL,
  position public.player_position NOT NULL,
  rarity public.player_rarity NOT NULL,
  sector public.player_sector NOT NULL,
  overall smallint NOT NULL CHECK (overall BETWEEN 1 AND 99),
  velocity smallint NOT NULL CHECK (velocity BETWEEN 1 AND 99),
  finishing smallint NOT NULL CHECK (finishing BETWEEN 1 AND 99),
  passing smallint NOT NULL CHECK (passing BETWEEN 1 AND 99),
  dribbling smallint NOT NULL CHECK (dribbling BETWEEN 1 AND 99),
  defending smallint NOT NULL CHECK (defending BETWEEN 1 AND 99),
  physical smallint NOT NULL CHECK (physical BETWEEN 1 AND 99),
  goalkeeping smallint NOT NULL CHECK (goalkeeping BETWEEN 1 AND 99),
  reference_value_cents integer NOT NULL CHECK (reference_value_cents BETWEEN 0 AND 10000),
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX idx_players_position ON public.players(position);
CREATE INDEX idx_players_rarity ON public.players(rarity);

GRANT SELECT ON public.players TO authenticated;
GRANT ALL ON public.players TO service_role;
ALTER TABLE public.players ENABLE ROW LEVEL SECURITY;

CREATE TRIGGER trg_players_updated_at
  BEFORE UPDATE ON public.players FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();

CREATE POLICY "players_authenticated_read" ON public.players
  FOR SELECT TO authenticated USING (true);

-- ---------- CLUB_PLAYERS (ownership) ----------
CREATE TABLE public.club_players (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  club_id uuid NOT NULL REFERENCES public.clubs(id) ON DELETE CASCADE,
  player_id uuid NOT NULL REFERENCES public.players(id) ON DELETE RESTRICT,
  acquired_at timestamptz NOT NULL DEFAULT now(),
  is_reserved boolean NOT NULL DEFAULT false, -- reserved by an open market listing or transfer offer
  CONSTRAINT club_players_unique_owner UNIQUE (player_id)
);
CREATE INDEX idx_club_players_club ON public.club_players(club_id);

GRANT SELECT ON public.club_players TO authenticated;
GRANT ALL ON public.club_players TO service_role;
ALTER TABLE public.club_players ENABLE ROW LEVEL SECURITY;

CREATE POLICY "club_players_read_own_or_admin" ON public.club_players
  FOR SELECT TO authenticated
  USING (
    EXISTS (SELECT 1 FROM public.clubs c WHERE c.id = club_id AND c.owner_id = auth.uid())
    OR public.has_role(auth.uid(), 'admin')
  );

-- ---------- INITIAL PACKS ----------
CREATE TABLE public.initial_packs (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  club_id uuid NOT NULL REFERENCES public.clubs(id) ON DELETE CASCADE,
  opened_at timestamptz,
  created_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT initial_packs_one_per_club UNIQUE (club_id)
);
GRANT SELECT ON public.initial_packs TO authenticated;
GRANT ALL ON public.initial_packs TO service_role;
ALTER TABLE public.initial_packs ENABLE ROW LEVEL SECURITY;

CREATE POLICY "initial_packs_owner_read" ON public.initial_packs
  FOR SELECT TO authenticated
  USING (
    EXISTS (SELECT 1 FROM public.clubs c WHERE c.id = club_id AND c.owner_id = auth.uid())
    OR public.has_role(auth.uid(), 'admin')
  );

CREATE TABLE public.initial_pack_items (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  pack_id uuid NOT NULL REFERENCES public.initial_packs(id) ON DELETE CASCADE,
  player_id uuid NOT NULL REFERENCES public.players(id) ON DELETE RESTRICT,
  slot smallint NOT NULL CHECK (slot BETWEEN 1 AND 10),
  UNIQUE (pack_id, player_id),
  UNIQUE (pack_id, slot)
);
GRANT SELECT ON public.initial_pack_items TO authenticated;
GRANT ALL ON public.initial_pack_items TO service_role;
ALTER TABLE public.initial_pack_items ENABLE ROW LEVEL SECURITY;

CREATE POLICY "initial_pack_items_owner_read" ON public.initial_pack_items
  FOR SELECT TO authenticated
  USING (
    EXISTS (
      SELECT 1 FROM public.initial_packs p
      JOIN public.clubs c ON c.id = p.club_id
      WHERE p.id = pack_id AND c.owner_id = auth.uid()
    ) OR public.has_role(auth.uid(), 'admin')
  );

-- ---------- WALLET TRANSACTIONS (ledger) ----------
CREATE TABLE public.wallet_transactions (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  club_id uuid NOT NULL REFERENCES public.clubs(id) ON DELETE RESTRICT,
  amount_cents integer NOT NULL, -- signed: positive credit, negative debit
  balance_after_cents integer NOT NULL CHECK (balance_after_cents >= 0 AND balance_after_cents <= 10000),
  kind public.wallet_transaction_type NOT NULL,
  reference_table text,
  reference_id uuid,
  memo text,
  created_at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX idx_wallet_tx_club ON public.wallet_transactions(club_id, created_at DESC);

GRANT SELECT ON public.wallet_transactions TO authenticated;
GRANT ALL ON public.wallet_transactions TO service_role;
ALTER TABLE public.wallet_transactions ENABLE ROW LEVEL SECURITY;

CREATE POLICY "wallet_tx_owner_read" ON public.wallet_transactions
  FOR SELECT TO authenticated
  USING (
    EXISTS (SELECT 1 FROM public.clubs c WHERE c.id = club_id AND c.owner_id = auth.uid())
    OR public.has_role(auth.uid(), 'admin')
  );

-- ---------- INTERNAL wallet helpers ----------
CREATE OR REPLACE FUNCTION public._credit_wallet(
  _club_id uuid, _amount_cents integer, _kind public.wallet_transaction_type,
  _ref_table text, _ref_id uuid, _memo text
) RETURNS integer LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $$
DECLARE _new_balance integer;
BEGIN
  IF _amount_cents <= 0 THEN RAISE EXCEPTION 'credit_must_be_positive'; END IF;
  UPDATE public.clubs SET balance_cents = balance_cents + _amount_cents
    WHERE id = _club_id RETURNING balance_cents INTO _new_balance;
  IF _new_balance IS NULL THEN RAISE EXCEPTION 'club_not_found'; END IF;
  INSERT INTO public.wallet_transactions
    (club_id, amount_cents, balance_after_cents, kind, reference_table, reference_id, memo)
    VALUES (_club_id, _amount_cents, _new_balance, _kind, _ref_table, _ref_id, _memo);
  RETURN _new_balance;
END; $$;
REVOKE ALL ON FUNCTION public._credit_wallet(uuid, integer, public.wallet_transaction_type, text, uuid, text) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public._credit_wallet(uuid, integer, public.wallet_transaction_type, text, uuid, text) TO service_role;

CREATE OR REPLACE FUNCTION public._debit_wallet(
  _club_id uuid, _amount_cents integer, _kind public.wallet_transaction_type,
  _ref_table text, _ref_id uuid, _memo text
) RETURNS integer LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $$
DECLARE _new_balance integer;
BEGIN
  IF _amount_cents <= 0 THEN RAISE EXCEPTION 'debit_must_be_positive'; END IF;
  UPDATE public.clubs SET balance_cents = balance_cents - _amount_cents
    WHERE id = _club_id AND balance_cents >= _amount_cents
    RETURNING balance_cents INTO _new_balance;
  IF _new_balance IS NULL THEN RAISE EXCEPTION 'insufficient_balance_or_club_missing'; END IF;
  INSERT INTO public.wallet_transactions
    (club_id, amount_cents, balance_after_cents, kind, reference_table, reference_id, memo)
    VALUES (_club_id, -_amount_cents, _new_balance, _kind, _ref_table, _ref_id, _memo);
  RETURN _new_balance;
END; $$;
REVOKE ALL ON FUNCTION public._debit_wallet(uuid, integer, public.wallet_transaction_type, text, uuid, text) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public._debit_wallet(uuid, integer, public.wallet_transaction_type, text, uuid, text) TO service_role;

-- ---------- RPC create_club ----------
CREATE OR REPLACE FUNCTION public.create_club(
  _name text, _abbreviation text, _badge_code text
) RETURNS uuid LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $$
DECLARE
  _uid uuid := auth.uid();
  _profile public.profiles%ROWTYPE;
  _league public.leagues%ROWTYPE;
  _badge public.club_badges%ROWTYPE;
  _abbr text := UPPER(_abbreviation);
  _club_id uuid;
BEGIN
  IF _uid IS NULL THEN RAISE EXCEPTION 'unauthenticated'; END IF;

  SELECT * INTO _profile FROM public.profiles WHERE id = _uid FOR UPDATE;
  IF _profile.id IS NULL THEN RAISE EXCEPTION 'profile_not_found'; END IF;
  IF _profile.status <> 'approved' THEN RAISE EXCEPTION 'profile_not_approved'; END IF;

  IF EXISTS (SELECT 1 FROM public.clubs WHERE owner_id = _uid) THEN
    RAISE EXCEPTION 'club_already_exists';
  END IF;

  SELECT * INTO _league FROM public.leagues WHERE slug = 'bagreleirao' FOR UPDATE;
  IF _league.id IS NULL THEN RAISE EXCEPTION 'league_missing'; END IF;
  IF _league.status <> 'setup' THEN RAISE EXCEPTION 'league_not_in_setup'; END IF;

  IF (SELECT COUNT(*) FROM public.clubs WHERE league_id = _league.id) >= _league.max_clubs THEN
    RAISE EXCEPTION 'league_full';
  END IF;

  IF _name IS NULL OR char_length(trim(_name)) < 3 OR char_length(_name) > 24 THEN
    RAISE EXCEPTION 'invalid_name';
  END IF;
  IF _abbr !~ '^[A-Z]{2,4}$' THEN RAISE EXCEPTION 'invalid_abbreviation'; END IF;

  SELECT * INTO _badge FROM public.club_badges WHERE code = _badge_code AND is_active;
  IF _badge.id IS NULL THEN RAISE EXCEPTION 'invalid_badge'; END IF;

  INSERT INTO public.clubs (league_id, owner_id, name, abbreviation, badge_id, balance_cents)
    VALUES (_league.id, _uid, _name, _abbr, _badge.id, 0)
    RETURNING id INTO _club_id;

  -- Initial credit R$ 10,00
  PERFORM public._credit_wallet(_club_id, 1000, 'initial_credit', 'clubs', _club_id, 'saldo inicial');

  -- Create closed initial pack
  INSERT INTO public.initial_packs (club_id) VALUES (_club_id);

  RETURN _club_id;
END; $$;
REVOKE ALL ON FUNCTION public.create_club(text, text, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.create_club(text, text, text) TO authenticated;

-- ---------- RPC open_initial_pack ----------
CREATE OR REPLACE FUNCTION public.open_initial_pack(_club_id uuid)
RETURNS TABLE(player_id uuid, slot smallint)
LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $$
DECLARE
  _uid uuid := auth.uid();
  _club public.clubs%ROWTYPE;
  _pack public.initial_packs%ROWTYPE;
  _league public.leagues%ROWTYPE;
  _profile_status public.user_status;
  _picked_ids uuid[];
BEGIN
  IF _uid IS NULL THEN RAISE EXCEPTION 'unauthenticated'; END IF;

  SELECT status INTO _profile_status FROM public.profiles WHERE id = _uid;
  IF _profile_status IS NULL THEN RAISE EXCEPTION 'profile_not_found'; END IF;
  IF _profile_status <> 'approved' THEN RAISE EXCEPTION 'profile_not_approved'; END IF;

  SELECT * INTO _club FROM public.clubs WHERE id = _club_id FOR UPDATE;
  IF _club.id IS NULL THEN RAISE EXCEPTION 'club_not_found'; END IF;
  IF _club.owner_id <> _uid THEN RAISE EXCEPTION 'not_club_owner'; END IF;

  SELECT * INTO _league FROM public.leagues WHERE id = _club.league_id;
  IF _league.status <> 'setup' THEN RAISE EXCEPTION 'league_not_in_setup'; END IF;

  SELECT * INTO _pack FROM public.initial_packs WHERE club_id = _club_id FOR UPDATE;
  IF _pack.id IS NULL THEN RAISE EXCEPTION 'pack_not_found'; END IF;
  IF _pack.opened_at IS NOT NULL THEN RAISE EXCEPTION 'pack_already_opened'; END IF;

  -- Pick 10 random players not currently owned. FOR UPDATE SKIP LOCKED on club_players
  -- would block, so instead we lock the pack row (done above) and rely on the unique
  -- constraint club_players_unique_owner as a hard concurrency guard.
  SELECT ARRAY(
    SELECT p.id
    FROM public.players p
    WHERE NOT EXISTS (SELECT 1 FROM public.club_players cp WHERE cp.player_id = p.id)
    ORDER BY random()
    LIMIT 10
  ) INTO _picked_ids;

  IF array_length(_picked_ids, 1) < 10 THEN
    RAISE EXCEPTION 'not_enough_players_available';
  END IF;

  -- Insert ownership rows; unique constraint prevents duplicates across concurrent calls.
  INSERT INTO public.club_players (club_id, player_id)
    SELECT _club_id, unnest(_picked_ids);

  -- Insert pack items with slot numbering
  INSERT INTO public.initial_pack_items (pack_id, player_id, slot)
    SELECT _pack.id, pid, (idx)::smallint
    FROM unnest(_picked_ids) WITH ORDINALITY AS t(pid, idx);

  UPDATE public.initial_packs SET opened_at = now() WHERE id = _pack.id;

  RETURN QUERY
    SELECT ipi.player_id, ipi.slot
    FROM public.initial_pack_items ipi
    WHERE ipi.pack_id = _pack.id
    ORDER BY ipi.slot;
END; $$;
REVOKE ALL ON FUNCTION public.open_initial_pack(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.open_initial_pack(uuid) TO authenticated;
