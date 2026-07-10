-- =====================================================================
-- BAGREFUT - Closed 60-card economy, roster 5..10, wallet R$ 999,99
-- Forward-only migration. Do not edit previously applied migrations.
-- =====================================================================

-- ---------------------------------------------------------------------
-- Preflight: fail before changing contracts if current data is incompatible.
-- ---------------------------------------------------------------------
DO $$
BEGIN
  IF EXISTS (
    SELECT 1
    FROM public.club_players cp
    WHERE cp.club_id IS NOT NULL
    GROUP BY cp.club_id
    HAVING pg_catalog.count(*) > 10
  ) THEN
    RAISE EXCEPTION 'roster_above_new_maximum';
  END IF;

  IF EXISTS (
    SELECT 1
    FROM public.clubs c
    WHERE c.balance_cents > 99999
  ) THEN
    RAISE EXCEPTION 'wallet_above_new_maximum';
  END IF;

  IF EXISTS (
    SELECT 1
    FROM public.wallet_transactions wt
    WHERE wt.balance_after_cents > 99999
  ) THEN
    RAISE EXCEPTION 'wallet_ledger_above_new_maximum';
  END IF;
END;
$$;

-- ---------------------------------------------------------------------
-- Wallet: card/offer price stays capped at 10.000 cents (R$ 100,00).
-- Club balance cap becomes 99.999 cents (R$ 999,99).
-- ---------------------------------------------------------------------
ALTER TABLE public.clubs
  DROP CONSTRAINT IF EXISTS clubs_balance_cap;

ALTER TABLE public.clubs
  ADD CONSTRAINT clubs_balance_cap
  CHECK (balance_cents <= 99999);

ALTER TABLE public.wallet_transactions
  DROP CONSTRAINT IF EXISTS wallet_transactions_balance_after_cents_check;

ALTER TABLE public.wallet_transactions
  DROP CONSTRAINT IF EXISTS wallet_transactions_balance_cap;

ALTER TABLE public.wallet_transactions
  ADD CONSTRAINT wallet_transactions_balance_cap
  CHECK (balance_after_cents BETWEEN 0 AND 99999);

CREATE OR REPLACE FUNCTION public._credit_wallet(
  _club_id uuid,
  _amount_cents integer,
  _kind public.wallet_transaction_type,
  _ref_table text,
  _ref_id uuid,
  _memo text
)
RETURNS integer
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  _new_balance integer;
BEGIN
  IF _amount_cents <= 0 THEN
    RAISE EXCEPTION 'credit_must_be_positive';
  END IF;

  UPDATE public.clubs
  SET balance_cents = balance_cents + _amount_cents
  WHERE id = _club_id
    AND balance_cents <= 99999 - _amount_cents
  RETURNING balance_cents INTO _new_balance;

  IF _new_balance IS NULL THEN
    IF EXISTS (SELECT 1 FROM public.clubs c WHERE c.id = _club_id) THEN
      RAISE EXCEPTION 'wallet_balance_cap_exceeded';
    END IF;
    RAISE EXCEPTION 'club_not_found';
  END IF;

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
    _club_id,
    _amount_cents,
    _new_balance,
    _kind,
    _ref_table,
    _ref_id,
    _memo
  );

  RETURN _new_balance;
END;
$$;

REVOKE ALL ON FUNCTION public._credit_wallet(
  uuid,
  integer,
  public.wallet_transaction_type,
  text,
  uuid,
  text
) FROM PUBLIC, anon, authenticated;

GRANT EXECUTE ON FUNCTION public._credit_wallet(
  uuid,
  integer,
  public.wallet_transaction_type,
  text,
  uuid,
  text
) TO postgres, service_role;

-- ---------------------------------------------------------------------
-- Closed economy:
--   is_market_eligible = false -> unopened initial-pack pool
--   is_market_eligible = true  -> commercial stock created by club sales
-- Initial-pack cards are invisible and cannot be bought.
-- ---------------------------------------------------------------------
ALTER TABLE public.system_market_stock
  ADD COLUMN IF NOT EXISTS is_market_eligible boolean
  NOT NULL
  DEFAULT false;

UPDATE public.system_market_stock
SET is_market_eligible = true
WHERE acquired_from_club_id IS NOT NULL
  AND NOT is_market_eligible;

COMMENT ON COLUMN public.system_market_stock.is_market_eligible IS
  'false: initial-pack pool; true: commercial system-market stock';

CREATE INDEX IF NOT EXISTS idx_system_market_stock_commercial
  ON public.system_market_stock(acquired_at, club_player_id)
  WHERE is_market_eligible;

DROP POLICY IF EXISTS "system_market_stock_approved_read"
  ON public.system_market_stock;

CREATE POLICY "system_market_stock_approved_read"
ON public.system_market_stock
FOR SELECT
TO authenticated
USING (
  public.is_approved_user(auth.uid())
  AND (
    is_market_eligible
    OR public.has_role(auth.uid(), 'admin'::public.app_role)
  )
);

DROP POLICY IF EXISTS "club_players_approved_owner_admin_or_system_read"
  ON public.club_players;

DROP POLICY IF EXISTS "club_players_approved_owner_or_admin_read"
  ON public.club_players;

DROP POLICY IF EXISTS "club_players_read_own_or_admin"
  ON public.club_players;

CREATE POLICY "club_players_approved_owner_admin_or_system_read"
ON public.club_players
FOR SELECT
TO authenticated
USING (
  public.is_approved_user(auth.uid())
  AND (
    EXISTS (
      SELECT 1
      FROM public.clubs c
      WHERE c.id = club_players.club_id
        AND c.owner_id = auth.uid()
    )
    OR (
      club_players.club_id IS NULL
      AND EXISTS (
        SELECT 1
        FROM public.system_market_stock sms
        WHERE sms.club_player_id = club_players.id
          AND sms.is_market_eligible
      )
    )
    OR public.has_role(auth.uid(), 'admin'::public.app_role)
  )
);

-- Defense in depth: no club may finish a transaction above 10 cards.
CREATE OR REPLACE FUNCTION public.enforce_club_roster_maximum()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = ''
AS $$
DECLARE
  _club_id uuid;
  _roster_size integer;
BEGIN
  _club_id := NEW.club_id;

  IF _club_id IS NULL THEN
    RETURN NULL;
  END IF;

  SELECT pg_catalog.count(*)::integer
  INTO _roster_size
  FROM public.club_players cp
  WHERE cp.club_id = _club_id;

  IF _roster_size > 10 THEN
    RAISE EXCEPTION 'roster_maximum';
  END IF;

  RETURN NULL;
END;
$$;

REVOKE ALL ON FUNCTION public.enforce_club_roster_maximum()
  FROM PUBLIC, anon, authenticated;

DROP TRIGGER IF EXISTS trg_club_players_roster_maximum
  ON public.club_players;

CREATE CONSTRAINT TRIGGER trg_club_players_roster_maximum
AFTER INSERT OR UPDATE OF club_id
ON public.club_players
DEFERRABLE INITIALLY DEFERRED
FOR EACH ROW
EXECUTE FUNCTION public.enforce_club_roster_maximum();

-- ---------------------------------------------------------------------
-- Initial pack: consumes only unopened starter stock.
-- Commercial stock created by club sales is never used in future packs.
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
  _picked_card_ids uuid[];
  _opened_at timestamptz;
  _current_roster integer;
BEGIN
  IF _uid IS NULL THEN
    RAISE EXCEPTION 'unauthenticated';
  END IF;

  SELECT * INTO _profile
  FROM public.profiles
  WHERE id = _uid;

  IF _profile.id IS NULL THEN
    RAISE EXCEPTION 'profile_not_found';
  END IF;
  IF _profile.status <> 'approved' THEN
    RAISE EXCEPTION 'profile_not_approved';
  END IF;

  SELECT * INTO _club
  FROM public.clubs
  WHERE id = _club_id
  FOR UPDATE;

  IF _club.id IS NULL THEN
    RAISE EXCEPTION 'club_not_found';
  END IF;
  IF _club.owner_id <> _uid THEN
    RAISE EXCEPTION 'not_club_owner';
  END IF;

  SELECT pg_catalog.count(*)::integer
  INTO _current_roster
  FROM public.club_players cp
  WHERE cp.club_id = _club.id;

  IF _current_roster <> 0 THEN
    RAISE EXCEPTION 'initial_pack_requires_empty_roster';
  END IF;

  SELECT * INTO _league
  FROM public.leagues
  WHERE id = _club.league_id;

  IF _league.id IS NULL THEN
    RAISE EXCEPTION 'league_not_found';
  END IF;
  IF _league.status <> 'setup' THEN
    RAISE EXCEPTION 'league_not_in_setup';
  END IF;

  SELECT * INTO _pack
  FROM public.initial_packs
  WHERE club_id = _club_id
  FOR UPDATE;

  IF _pack.id IS NULL THEN
    RAISE EXCEPTION 'pack_not_found';
  END IF;
  IF _pack.opened_at IS NOT NULL THEN
    RAISE EXCEPTION 'pack_already_opened';
  END IF;

  SELECT ARRAY(
    SELECT sms.club_player_id
    FROM public.system_market_stock sms
    JOIN public.club_players cp ON cp.id = sms.club_player_id
    JOIN public.players p ON p.id = cp.player_id
    WHERE cp.club_id IS NULL
      AND cp.is_reserved = false
      AND NOT sms.is_market_eligible
    ORDER BY pg_catalog.random()
    LIMIT 10
    FOR UPDATE OF sms, cp SKIP LOCKED
  )
  INTO _picked_card_ids;

  IF COALESCE(pg_catalog.array_length(_picked_card_ids, 1), 0) <> 10 THEN
    RAISE EXCEPTION 'not_enough_players_available';
  END IF;

  DELETE FROM public.system_market_stock sms
  WHERE sms.club_player_id = ANY(_picked_card_ids)
    AND NOT sms.is_market_eligible;

  UPDATE public.club_players cp
  SET club_id = _club_id,
      acquired_at = pg_catalog.now(),
      is_reserved = false
  WHERE cp.id = ANY(_picked_card_ids)
    AND cp.club_id IS NULL;

  INSERT INTO public.initial_pack_items(pack_id, player_id, slot)
  SELECT _pack.id, cp.player_id, picked.slot::smallint
  FROM pg_catalog.unnest(_picked_card_ids)
    WITH ORDINALITY AS picked(club_player_id, slot)
  JOIN public.club_players cp ON cp.id = picked.club_player_id;

  UPDATE public.initial_packs
  SET opened_at = pg_catalog.now()
  WHERE id = _pack.id
    AND opened_at IS NULL
  RETURNING public.initial_packs.opened_at INTO _opened_at;

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

-- ---------------------------------------------------------------------
-- System sale: club -> system, 50% reference, roster minimum 5.
-- Sold card becomes commercial stock.
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.sell_player_to_system(_club_player_id uuid)
RETURNS TABLE(
  club_player_id uuid,
  player_id uuid,
  price_cents integer,
  balance_cents integer,
  roster_size integer
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  _uid uuid := auth.uid();
  _profile public.profiles%ROWTYPE;
  _club public.clubs%ROWTYPE;
  _card public.club_players%ROWTYPE;
  _player public.players%ROWTYPE;
  _price integer;
  _new_balance integer;
  _new_roster_size integer;
BEGIN
  IF _uid IS NULL THEN
    RAISE EXCEPTION 'unauthenticated';
  END IF;

  SELECT * INTO _profile
  FROM public.profiles
  WHERE id = _uid;

  IF _profile.id IS NULL OR _profile.status <> 'approved' THEN
    RAISE EXCEPTION 'profile_not_approved';
  END IF;

  SELECT * INTO _club
  FROM public.clubs
  WHERE owner_id = _uid
  FOR UPDATE;

  IF _club.id IS NULL THEN
    RAISE EXCEPTION 'club_not_found';
  END IF;

  SELECT * INTO _card
  FROM public.club_players
  WHERE id = _club_player_id
  FOR UPDATE;

  IF _card.id IS NULL OR _card.club_id <> _club.id THEN
    RAISE EXCEPTION 'player_not_owned';
  END IF;

  IF _card.is_reserved THEN
    RAISE EXCEPTION 'card_reserved';
  END IF;

  IF EXISTS (
    SELECT 1
    FROM public.system_market_stock sms
    WHERE sms.club_player_id = _card.id
    FOR UPDATE
  ) THEN
    RAISE EXCEPTION 'player_already_in_system_stock';
  END IF;

  SELECT * INTO _player
  FROM public.players
  WHERE id = _card.player_id
  FOR UPDATE;

  SELECT pg_catalog.count(*)::integer
  INTO _new_roster_size
  FROM public.club_players cp
  WHERE cp.club_id = _club.id;

  IF _new_roster_size <= 5 THEN
    RAISE EXCEPTION 'roster_minimum_reached';
  END IF;

  _price := pg_catalog.floor(_player.reference_value_cents / 2.0)::integer;

  IF _club.balance_cents + _price > 99999 THEN
    RAISE EXCEPTION 'wallet_balance_cap_exceeded';
  END IF;

  UPDATE public.club_players
  SET club_id = NULL,
      acquired_at = pg_catalog.now(),
      is_reserved = false
  WHERE id = _card.id;

  INSERT INTO public.system_market_stock(
    club_player_id,
    acquired_from_club_id,
    acquired_price_cents,
    is_market_eligible
  )
  VALUES (
    _card.id,
    _club.id,
    _price,
    true
  );

  _new_balance := public._credit_wallet(
    _club.id,
    _price,
    'system_sale',
    'club_players',
    _card.id,
    'venda ao sistema'
  );

  _new_roster_size := _new_roster_size - 1;

  RETURN QUERY
  SELECT
    _card.id,
    _player.id,
    _price,
    _new_balance,
    _new_roster_size;
END;
$$;

REVOKE ALL ON FUNCTION public.sell_player_to_system(uuid)
  FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.sell_player_to_system(uuid)
  TO authenticated;

-- ---------------------------------------------------------------------
-- System purchase: only commercial stock, 100% reference, roster max 10.
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.buy_player_from_system(_club_player_id uuid)
RETURNS TABLE(
  club_player_id uuid,
  player_id uuid,
  price_cents integer,
  balance_cents integer,
  roster_size integer
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  _uid uuid := auth.uid();
  _profile public.profiles%ROWTYPE;
  _club public.clubs%ROWTYPE;
  _card public.club_players%ROWTYPE;
  _player public.players%ROWTYPE;
  _stock public.system_market_stock%ROWTYPE;
  _price integer;
  _new_balance integer;
  _new_roster_size integer;
BEGIN
  IF _uid IS NULL THEN
    RAISE EXCEPTION 'unauthenticated';
  END IF;

  SELECT * INTO _profile
  FROM public.profiles
  WHERE id = _uid;

  IF _profile.id IS NULL OR _profile.status <> 'approved' THEN
    RAISE EXCEPTION 'profile_not_approved';
  END IF;

  SELECT * INTO _club
  FROM public.clubs
  WHERE owner_id = _uid
  FOR UPDATE;

  IF _club.id IS NULL THEN
    RAISE EXCEPTION 'club_not_found';
  END IF;

  SELECT * INTO _card
  FROM public.club_players
  WHERE id = _club_player_id
  FOR UPDATE;

  IF _card.id IS NULL OR _card.club_id IS NOT NULL THEN
    RAISE EXCEPTION 'player_not_in_system_stock';
  END IF;

  SELECT * INTO _stock
  FROM public.system_market_stock
  WHERE club_player_id = _card.id
    AND is_market_eligible
  FOR UPDATE;

  IF _stock.club_player_id IS NULL THEN
    RAISE EXCEPTION 'player_not_in_system_stock';
  END IF;

  SELECT * INTO _player
  FROM public.players
  WHERE id = _card.player_id
  FOR UPDATE;

  SELECT pg_catalog.count(*)::integer
  INTO _new_roster_size
  FROM public.club_players cp
  WHERE cp.club_id = _club.id;

  IF _new_roster_size >= 10 THEN
    RAISE EXCEPTION 'roster_maximum_reached';
  END IF;

  _price := _player.reference_value_cents;

  _new_balance := public._debit_wallet(
    _club.id,
    _price,
    'system_purchase',
    'club_players',
    _card.id,
    'compra do sistema'
  );

  DELETE FROM public.system_market_stock
  WHERE club_player_id = _card.id
    AND is_market_eligible;

  UPDATE public.club_players
  SET club_id = _club.id,
      acquired_at = pg_catalog.now(),
      is_reserved = false
  WHERE id = _card.id;

  _new_roster_size := _new_roster_size + 1;

  RETURN QUERY
  SELECT
    _card.id,
    _player.id,
    _price,
    _new_balance,
    _new_roster_size;
END;
$$;

REVOKE ALL ON FUNCTION public.buy_player_from_system(uuid)
  FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.buy_player_from_system(uuid)
  TO authenticated;

-- ---------------------------------------------------------------------
-- Fixed-price P2P purchase: buyer max 10, seller min 5,
-- recipient wallet cap 99.999 cents.
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.buy_market_listing(_listing_id uuid)
RETURNS TABLE(
  listing_id uuid,
  status public.market_listing_status,
  club_player_id uuid,
  price_cents integer,
  buyer_balance_cents integer,
  seller_balance_cents integer,
  buyer_roster_size integer,
  seller_roster_size integer,
  idempotent boolean
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  _uid uuid := auth.uid();
  _listing public.market_listings%ROWTYPE;
  _card public.club_players%ROWTYPE;
  _buyer public.clubs%ROWTYPE;
  _buyer_id uuid;
  _seller public.clubs%ROWTYPE;
  _buyer_balance integer;
  _seller_balance integer;
  _buyer_roster integer;
  _seller_roster integer;
BEGIN
  IF _uid IS NULL THEN
    RAISE EXCEPTION 'unauthenticated';
  END IF;
  IF NOT public.is_approved_user(_uid) THEN
    RAISE EXCEPTION 'profile_not_approved';
  END IF;

  SELECT * INTO _listing
  FROM public.market_listings ml
  WHERE ml.id = _listing_id
  FOR UPDATE;

  IF _listing.id IS NULL THEN
    RAISE EXCEPTION 'listing_not_found';
  END IF;
  IF _listing.status <> 'open' THEN
    RAISE EXCEPTION 'listing_not_open';
  END IF;

  SELECT * INTO _card
  FROM public.club_players cp
  WHERE cp.id = _listing.club_player_id
  FOR UPDATE;

  SELECT * INTO _buyer
  FROM public.clubs c
  WHERE c.owner_id = _uid;

  IF _buyer.id IS NULL THEN
    RAISE EXCEPTION 'club_not_found';
  END IF;
  IF _buyer.id = _listing.seller_club_id THEN
    RAISE EXCEPTION 'cannot_buy_own_listing';
  END IF;

  _buyer_id := _buyer.id;

  PERFORM 1
  FROM public.clubs c
  WHERE c.id IN (_buyer_id, _listing.seller_club_id)
  ORDER BY c.id
  FOR UPDATE;

  SELECT * INTO _buyer
  FROM public.clubs c
  WHERE c.id = _buyer_id;

  SELECT * INTO _seller
  FROM public.clubs c
  WHERE c.id = _listing.seller_club_id;

  IF _seller.id IS NULL THEN
    RAISE EXCEPTION 'club_not_found';
  END IF;
  IF _card.id IS NULL OR _card.club_id <> _seller.id THEN
    RAISE EXCEPTION 'listing_not_open';
  END IF;
  IF NOT _card.is_reserved THEN
    RAISE EXCEPTION 'listing_not_open';
  END IF;

  IF EXISTS (
    SELECT 1
    FROM public.transfer_offer_items toi
    JOIN public.transfer_offers o ON o.id = toi.offer_id
    WHERE toi.club_player_id = _card.id
      AND o.status = 'pending'
  ) THEN
    RAISE EXCEPTION 'player_in_pending_offer';
  END IF;

  SELECT pg_catalog.count(*)::integer
  INTO _buyer_roster
  FROM public.club_players cp
  WHERE cp.club_id = _buyer.id;

  SELECT pg_catalog.count(*)::integer
  INTO _seller_roster
  FROM public.club_players cp
  WHERE cp.club_id = _seller.id;

  IF _buyer_roster >= 10 THEN
    RAISE EXCEPTION 'roster_maximum';
  END IF;
  IF _seller_roster <= 5 THEN
    RAISE EXCEPTION 'roster_minimum';
  END IF;
  IF _buyer.balance_cents < _listing.price_cents THEN
    RAISE EXCEPTION 'insufficient_balance';
  END IF;
  IF _seller.balance_cents + _listing.price_cents > 99999 THEN
    RAISE EXCEPTION 'wallet_balance_cap_exceeded';
  END IF;

  _buyer_balance := public._debit_wallet(
    _buyer.id,
    _listing.price_cents,
    'market_purchase',
    'market_listings',
    _listing.id,
    'compra P2P'
  );

  _seller_balance := public._credit_wallet(
    _seller.id,
    _listing.price_cents,
    'market_sale',
    'market_listings',
    _listing.id,
    'venda P2P'
  );

  UPDATE public.club_players
  SET club_id = _buyer.id,
      acquired_at = pg_catalog.now(),
      is_reserved = false
  WHERE id = _card.id;

  UPDATE public.market_listings
  SET status = 'sold',
      closed_at = pg_catalog.now()
  WHERE id = _listing.id
  RETURNING * INTO _listing;

  RETURN QUERY
  SELECT
    _listing.id,
    _listing.status,
    _card.id,
    _listing.price_cents,
    _buyer_balance,
    _seller_balance,
    _buyer_roster + 1,
    _seller_roster - 1,
    false;
END;
$$;

REVOKE ALL ON FUNCTION public.buy_market_listing(uuid)
  FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.buy_market_listing(uuid)
  TO authenticated;

-- ---------------------------------------------------------------------
-- Direct transfer offer: both projected rosters must remain 5..10.
-- Cash per offer remains capped at 10.000 cents.
-- Recipient wallet cap becomes 99.999 cents.
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.create_transfer_offer(
  _to_club_id uuid,
  _from_club_player_ids uuid[],
  _to_club_player_ids uuid[],
  _cash_cents integer DEFAULT 0,
  _expires_at timestamptz DEFAULT pg_catalog.now() + interval '24 hours'
)
RETURNS TABLE(
  offer_id uuid,
  status public.transfer_offer_status,
  expires_at timestamptz,
  reserved_count integer,
  idempotent boolean
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  _uid uuid := auth.uid();
  _from_club public.clubs%ROWTYPE;
  _to_club public.clubs%ROWTYPE;
  _from_club_id uuid;
  _target_club_id uuid;
  _offer public.transfer_offers%ROWTYPE;
  _from_ids uuid[] := COALESCE(_from_club_player_ids, ARRAY[]::uuid[]);
  _to_ids uuid[] := COALESCE(_to_club_player_ids, ARRAY[]::uuid[]);
  _all_ids uuid[];
  _from_roster integer;
  _to_roster integer;
  _from_count integer := COALESCE(pg_catalog.array_length(_from_ids, 1), 0);
  _to_count integer := COALESCE(pg_catalog.array_length(_to_ids, 1), 0);
BEGIN
  PERFORM public._expire_transfer_offers(pg_catalog.now());

  IF _uid IS NULL THEN
    RAISE EXCEPTION 'unauthenticated';
  END IF;
  IF NOT public.is_approved_user(_uid) THEN
    RAISE EXCEPTION 'profile_not_approved';
  END IF;
  IF _cash_cents < 0 OR _cash_cents > 10000 THEN
    RAISE EXCEPTION 'invalid_cash';
  END IF;
  IF _expires_at <= pg_catalog.now() THEN
    RAISE EXCEPTION 'offer_expired';
  END IF;
  IF _from_count > 5 OR _to_count > 5 THEN
    RAISE EXCEPTION 'invalid_offer_size';
  END IF;
  IF _from_count = 0 AND _to_count = 0 AND _cash_cents = 0 THEN
    RAISE EXCEPTION 'invalid_offer_empty';
  END IF;

  IF (
    SELECT pg_catalog.count(DISTINCT u.id)
    FROM pg_catalog.unnest(_from_ids) AS u(id)
  ) <> _from_count THEN
    RAISE EXCEPTION 'duplicate_player';
  END IF;

  IF (
    SELECT pg_catalog.count(DISTINCT u.id)
    FROM pg_catalog.unnest(_to_ids) AS u(id)
  ) <> _to_count THEN
    RAISE EXCEPTION 'duplicate_player';
  END IF;

  IF EXISTS (
    SELECT 1
    FROM pg_catalog.unnest(_from_ids) AS f(id)
    JOIN pg_catalog.unnest(_to_ids) AS t(id) ON t.id = f.id
  ) THEN
    RAISE EXCEPTION 'duplicate_player';
  END IF;

  SELECT * INTO _from_club
  FROM public.clubs c
  WHERE c.owner_id = _uid;

  IF _from_club.id IS NULL THEN
    RAISE EXCEPTION 'club_not_found';
  END IF;
  IF _from_club.id = _to_club_id THEN
    RAISE EXCEPTION 'invalid_target_club';
  END IF;

  SELECT * INTO _to_club
  FROM public.clubs c
  WHERE c.id = _to_club_id
    AND c.is_active;

  IF _to_club.id IS NULL THEN
    RAISE EXCEPTION 'club_not_found';
  END IF;

  _from_club_id := _from_club.id;
  _target_club_id := _to_club.id;

  PERFORM 1
  FROM public.clubs c
  WHERE c.id IN (_from_club_id, _target_club_id)
  ORDER BY c.id
  FOR UPDATE;

  SELECT * INTO _from_club
  FROM public.clubs c
  WHERE c.id = _from_club_id;

  SELECT * INTO _to_club
  FROM public.clubs c
  WHERE c.id = _target_club_id;

  _all_ids := _from_ids || _to_ids;

  PERFORM 1
  FROM public.club_players cp
  WHERE cp.id = ANY(_all_ids)
  ORDER BY cp.id
  FOR UPDATE;

  IF (
    SELECT pg_catalog.count(*)
    FROM public.club_players cp
    WHERE cp.id = ANY(_from_ids)
      AND cp.club_id = _from_club.id
  ) <> _from_count THEN
    RAISE EXCEPTION 'player_not_owned';
  END IF;

  IF (
    SELECT pg_catalog.count(*)
    FROM public.club_players cp
    WHERE cp.id = ANY(_to_ids)
      AND cp.club_id = _to_club.id
  ) <> _to_count THEN
    RAISE EXCEPTION 'player_not_owned';
  END IF;

  IF EXISTS (
    SELECT 1
    FROM public.club_players cp
    WHERE cp.id = ANY(_all_ids)
      AND cp.is_reserved
  ) THEN
    RAISE EXCEPTION 'player_reserved';
  END IF;

  IF EXISTS (
    SELECT 1
    FROM public.market_listings ml
    WHERE ml.club_player_id = ANY(_all_ids)
      AND ml.status = 'open'
  ) THEN
    RAISE EXCEPTION 'player_already_listed';
  END IF;

  IF EXISTS (
    SELECT 1
    FROM public.transfer_offer_items toi
    JOIN public.transfer_offers o ON o.id = toi.offer_id
    WHERE toi.club_player_id = ANY(_all_ids)
      AND o.status = 'pending'
  ) THEN
    RAISE EXCEPTION 'player_in_pending_offer';
  END IF;

  SELECT pg_catalog.count(*)::integer
  INTO _from_roster
  FROM public.club_players cp
  WHERE cp.club_id = _from_club.id;

  SELECT pg_catalog.count(*)::integer
  INTO _to_roster
  FROM public.club_players cp
  WHERE cp.club_id = _to_club.id;

  IF _from_roster - _from_count + _to_count NOT BETWEEN 5 AND 10 THEN
    RAISE EXCEPTION '%', CASE
      WHEN _from_roster - _from_count + _to_count < 5
        THEN 'roster_minimum'
      ELSE 'roster_maximum'
    END;
  END IF;

  IF _to_roster - _to_count + _from_count NOT BETWEEN 5 AND 10 THEN
    RAISE EXCEPTION '%', CASE
      WHEN _to_roster - _to_count + _from_count < 5
        THEN 'roster_minimum'
      ELSE 'roster_maximum'
    END;
  END IF;

  IF _from_club.balance_cents < _cash_cents THEN
    RAISE EXCEPTION 'insufficient_balance';
  END IF;

  IF _to_club.balance_cents + _cash_cents > 99999 THEN
    RAISE EXCEPTION 'wallet_balance_cap_exceeded';
  END IF;

  INSERT INTO public.transfer_offers(
    from_club_id,
    to_club_id,
    cash_cents,
    status,
    expires_at
  )
  VALUES (
    _from_club.id,
    _to_club.id,
    _cash_cents,
    'pending',
    _expires_at
  )
  RETURNING * INTO _offer;

  INSERT INTO public.transfer_offer_items(
    offer_id,
    club_player_id,
    side
  )
  SELECT
    _offer.id,
    u.club_player_id,
    'from'
  FROM pg_catalog.unnest(_from_ids) AS u(club_player_id);

  INSERT INTO public.transfer_offer_items(
    offer_id,
    club_player_id,
    side
  )
  SELECT
    _offer.id,
    u.club_player_id,
    'to'
  FROM pg_catalog.unnest(_to_ids) AS u(club_player_id);

  UPDATE public.club_players
  SET is_reserved = true
  WHERE id = ANY(_all_ids);

  RETURN QUERY
  SELECT
    _offer.id,
    _offer.status,
    _offer.expires_at,
    _from_count + _to_count,
    false;
END;
$$;

REVOKE ALL ON FUNCTION public.create_transfer_offer(
  uuid,
  uuid[],
  uuid[],
  integer,
  timestamptz
) FROM PUBLIC, anon, authenticated;

GRANT EXECUTE ON FUNCTION public.create_transfer_offer(
  uuid,
  uuid[],
  uuid[],
  integer,
  timestamptz
) TO authenticated;

CREATE OR REPLACE FUNCTION public.accept_transfer_offer(_offer_id uuid)
RETURNS TABLE(
  offer_id uuid,
  status public.transfer_offer_status,
  resolved_at timestamptz,
  idempotent boolean
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  _uid uuid := auth.uid();
  _caller_club_id uuid;
  _offer public.transfer_offers%ROWTYPE;
  _from_club public.clubs%ROWTYPE;
  _to_club public.clubs%ROWTYPE;
  _from_count integer;
  _to_count integer;
  _from_roster integer;
  _to_roster integer;
  _resolved_at timestamptz;
BEGIN
  PERFORM public._expire_transfer_offers(pg_catalog.now());

  IF _uid IS NULL THEN
    RAISE EXCEPTION 'unauthenticated';
  END IF;
  IF NOT public.is_approved_user(_uid) THEN
    RAISE EXCEPTION 'profile_not_approved';
  END IF;

  SELECT c.id INTO _caller_club_id
  FROM public.clubs c
  WHERE c.owner_id = _uid;

  IF _caller_club_id IS NULL THEN
    RAISE EXCEPTION 'club_not_found';
  END IF;

  SELECT * INTO _offer
  FROM public.transfer_offers o
  WHERE o.id = _offer_id
  FOR UPDATE;

  IF _offer.id IS NULL THEN
    RAISE EXCEPTION 'offer_not_found';
  END IF;
  IF _offer.to_club_id <> _caller_club_id THEN
    RAISE EXCEPTION 'offer_not_recipient';
  END IF;

  IF _offer.status = 'accepted' THEN
    RETURN QUERY
    SELECT
      _offer.id,
      _offer.status,
      _offer.resolved_at,
      true;
    RETURN;
  END IF;

  IF _offer.status = 'expired'
    OR _offer.expires_at <= pg_catalog.now() THEN
    RAISE EXCEPTION 'offer_expired';
  END IF;

  IF _offer.status <> 'pending' THEN
    RAISE EXCEPTION 'offer_not_pending';
  END IF;

  PERFORM 1
  FROM public.clubs c
  WHERE c.id IN (_offer.from_club_id, _offer.to_club_id)
  ORDER BY c.id
  FOR UPDATE;

  SELECT * INTO _from_club
  FROM public.clubs c
  WHERE c.id = _offer.from_club_id;

  SELECT * INTO _to_club
  FROM public.clubs c
  WHERE c.id = _offer.to_club_id;

  PERFORM 1
  FROM public.club_players cp
  JOIN public.transfer_offer_items toi
    ON toi.club_player_id = cp.id
  WHERE toi.offer_id = _offer.id
  ORDER BY cp.id
  FOR UPDATE OF cp;

  SELECT pg_catalog.count(*)::integer
  INTO _from_count
  FROM public.transfer_offer_items toi
  WHERE toi.offer_id = _offer.id
    AND toi.side = 'from';

  SELECT pg_catalog.count(*)::integer
  INTO _to_count
  FROM public.transfer_offer_items toi
  WHERE toi.offer_id = _offer.id
    AND toi.side = 'to';

  IF EXISTS (
    SELECT 1
    FROM public.transfer_offer_items toi
    LEFT JOIN public.club_players cp
      ON cp.id = toi.club_player_id
    WHERE toi.offer_id = _offer.id
      AND (
        cp.id IS NULL
        OR NOT cp.is_reserved
        OR (
          toi.side = 'from'
          AND cp.club_id <> _offer.from_club_id
        )
        OR (
          toi.side = 'to'
          AND cp.club_id <> _offer.to_club_id
        )
      )
  ) THEN
    RAISE EXCEPTION 'player_not_owned';
  END IF;

  IF EXISTS (
    SELECT 1
    FROM public.transfer_offer_items toi
    JOIN public.market_listings ml
      ON ml.club_player_id = toi.club_player_id
    WHERE toi.offer_id = _offer.id
      AND ml.status = 'open'
  ) THEN
    RAISE EXCEPTION 'player_already_listed';
  END IF;

  SELECT pg_catalog.count(*)::integer
  INTO _from_roster
  FROM public.club_players cp
  WHERE cp.club_id = _from_club.id;

  SELECT pg_catalog.count(*)::integer
  INTO _to_roster
  FROM public.club_players cp
  WHERE cp.club_id = _to_club.id;

  IF _from_roster - _from_count + _to_count NOT BETWEEN 5 AND 10 THEN
    RAISE EXCEPTION '%', CASE
      WHEN _from_roster - _from_count + _to_count < 5
        THEN 'roster_minimum'
      ELSE 'roster_maximum'
    END;
  END IF;

  IF _to_roster - _to_count + _from_count NOT BETWEEN 5 AND 10 THEN
    RAISE EXCEPTION '%', CASE
      WHEN _to_roster - _to_count + _from_count < 5
        THEN 'roster_minimum'
      ELSE 'roster_maximum'
    END;
  END IF;

  IF _from_club.balance_cents < _offer.cash_cents THEN
    RAISE EXCEPTION 'insufficient_balance';
  END IF;

  IF _to_club.balance_cents + _offer.cash_cents > 99999 THEN
    RAISE EXCEPTION 'wallet_balance_cap_exceeded';
  END IF;

  UPDATE public.club_players cp
  SET club_id = _offer.to_club_id,
      acquired_at = pg_catalog.now(),
      is_reserved = false
  FROM public.transfer_offer_items toi
  WHERE toi.offer_id = _offer.id
    AND toi.side = 'from'
    AND cp.id = toi.club_player_id;

  UPDATE public.club_players cp
  SET club_id = _offer.from_club_id,
      acquired_at = pg_catalog.now(),
      is_reserved = false
  FROM public.transfer_offer_items toi
  WHERE toi.offer_id = _offer.id
    AND toi.side = 'to'
    AND cp.id = toi.club_player_id;

  IF _offer.cash_cents > 0 THEN
    PERFORM public._debit_wallet(
      _offer.from_club_id,
      _offer.cash_cents,
      'transfer_cash',
      'transfer_offers',
      _offer.id,
      'dinheiro em troca P2P'
    );

    PERFORM public._credit_wallet(
      _offer.to_club_id,
      _offer.cash_cents,
      'transfer_cash',
      'transfer_offers',
      _offer.id,
      'dinheiro recebido em troca P2P'
    );
  END IF;

  _resolved_at := pg_catalog.now();

  UPDATE public.transfer_offers
  SET status = 'accepted',
      resolved_at = _resolved_at
  WHERE id = _offer.id
  RETURNING * INTO _offer;

  RETURN QUERY
  SELECT
    _offer.id,
    _offer.status,
    _offer.resolved_at,
    false;
END;
$$;

REVOKE ALL ON FUNCTION public.accept_transfer_offer(uuid)
  FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.accept_transfer_offer(uuid)
  TO authenticated;
