-- =====================================================================
-- BAGREFUT - Usable system market, transactional P2P listings and trades
-- =====================================================================

-- The table was originally created with this check. Recreate it explicitly
-- in this forward-only migration so the side contract has a stable name.
ALTER TABLE public.transfer_offer_items
  DROP CONSTRAINT IF EXISTS transfer_offer_items_side_check;
ALTER TABLE public.transfer_offer_items
  ADD CONSTRAINT transfer_offer_items_side_check CHECK (side IN ('from', 'to'));

-- System stock is never reservable. This makes buy_player_from_system reject
-- any impossible reserved-system state at the data boundary as well.
ALTER TABLE public.club_players
  DROP CONSTRAINT IF EXISTS club_players_system_not_reserved;
ALTER TABLE public.club_players
  ADD CONSTRAINT club_players_system_not_reserved
  CHECK (club_id IS NOT NULL OR NOT is_reserved);

CREATE INDEX IF NOT EXISTS idx_transfer_offer_items_card
  ON public.transfer_offer_items(club_player_id, offer_id);
CREATE INDEX IF NOT EXISTS idx_transfer_offers_pending_expiry
  ON public.transfer_offers(expires_at, id)
  WHERE status = 'pending';

DROP POLICY IF EXISTS "market_listings_approved_read" ON public.market_listings;
CREATE POLICY "market_listings_approved_open_read"
ON public.market_listings
FOR SELECT
TO authenticated
USING (
  public.is_approved_user(auth.uid())
  AND status = 'open'
);

CREATE OR REPLACE FUNCTION public._release_transfer_offer_cards(_offer_id uuid)
RETURNS integer
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  _released integer;
BEGIN
  UPDATE public.club_players cp
  SET is_reserved = false
  WHERE cp.id IN (
    SELECT toi.club_player_id
    FROM public.transfer_offer_items toi
    WHERE toi.offer_id = _offer_id
  )
  AND NOT EXISTS (
    SELECT 1
    FROM public.market_listings ml
    WHERE ml.club_player_id = cp.id
      AND ml.status = 'open'
  )
  AND NOT EXISTS (
    SELECT 1
    FROM public.transfer_offer_items other_item
    JOIN public.transfer_offers other_offer ON other_offer.id = other_item.offer_id
    WHERE other_item.club_player_id = cp.id
      AND other_item.offer_id <> _offer_id
      AND other_offer.status = 'pending'
  );

  GET DIAGNOSTICS _released = ROW_COUNT;
  RETURN _released;
END;
$$;

REVOKE ALL ON FUNCTION public._release_transfer_offer_cards(uuid)
  FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public._release_transfer_offer_cards(uuid)
  TO postgres, service_role;

CREATE OR REPLACE FUNCTION public._expire_transfer_offers(
  _now timestamptz DEFAULT pg_catalog.now()
)
RETURNS integer
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  _offer record;
  _expired integer := 0;
BEGIN
  FOR _offer IN
    SELECT o.id
    FROM public.transfer_offers o
    WHERE o.status = 'pending'
      AND o.expires_at <= _now
    ORDER BY o.id
    FOR UPDATE SKIP LOCKED
  LOOP
    UPDATE public.transfer_offers
    SET status = 'expired',
        resolved_at = _now
    WHERE id = _offer.id
      AND status = 'pending';

    IF FOUND THEN
      PERFORM public._release_transfer_offer_cards(_offer.id);
      _expired := _expired + 1;
    END IF;
  END LOOP;

  RETURN _expired;
END;
$$;

REVOKE ALL ON FUNCTION public._expire_transfer_offers(timestamptz)
  FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public._expire_transfer_offers(timestamptz)
  TO postgres, service_role;

CREATE OR REPLACE FUNCTION public.list_market_listings(
  _position public.player_position DEFAULT NULL,
  _rarity public.player_rarity DEFAULT NULL,
  _min_overall integer DEFAULT NULL,
  _max_overall integer DEFAULT NULL,
  _max_price_cents integer DEFAULT NULL
)
RETURNS TABLE(
  listing_id uuid,
  seller_club_id uuid,
  seller_name text,
  seller_abbreviation text,
  club_player_id uuid,
  player_id uuid,
  player_name text,
  "position" public.player_position,
  rarity public.player_rarity,
  sector public.player_sector,
  overall smallint,
  velocity smallint,
  finishing smallint,
  passing smallint,
  dribbling smallint,
  defending smallint,
  physical smallint,
  goalkeeping smallint,
  reference_value_cents integer,
  price_cents integer,
  created_at timestamptz,
  is_mine boolean
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  _uid uuid := auth.uid();
  _club_id uuid;
BEGIN
  IF _uid IS NULL THEN
    RAISE EXCEPTION 'unauthenticated';
  END IF;
  IF NOT public.is_approved_user(_uid) THEN
    RAISE EXCEPTION 'profile_not_approved';
  END IF;

  SELECT c.id INTO _club_id
  FROM public.clubs c
  WHERE c.owner_id = _uid;
  IF _club_id IS NULL THEN
    RAISE EXCEPTION 'club_not_found';
  END IF;

  IF _min_overall IS NOT NULL AND (_min_overall < 1 OR _min_overall > 99) THEN
    RAISE EXCEPTION 'invalid_overall';
  END IF;
  IF _max_overall IS NOT NULL AND (_max_overall < 1 OR _max_overall > 99) THEN
    RAISE EXCEPTION 'invalid_overall';
  END IF;
  IF _min_overall IS NOT NULL AND _max_overall IS NOT NULL AND _min_overall > _max_overall THEN
    RAISE EXCEPTION 'invalid_overall';
  END IF;
  IF _max_price_cents IS NOT NULL AND (_max_price_cents < 0 OR _max_price_cents > 10000) THEN
    RAISE EXCEPTION 'invalid_price';
  END IF;

  RETURN QUERY
  SELECT
    ml.id,
    c.id,
    c.name,
    c.abbreviation,
    cp.id,
    p.id,
    p.name,
    p.position,
    p.rarity,
    p.sector,
    p.overall,
    p.velocity,
    p.finishing,
    p.passing,
    p.dribbling,
    p.defending,
    p.physical,
    p.goalkeeping,
    p.reference_value_cents,
    ml.price_cents,
    ml.created_at,
    ml.seller_club_id = _club_id
  FROM public.market_listings ml
  JOIN public.clubs c ON c.id = ml.seller_club_id
  JOIN public.club_players cp ON cp.id = ml.club_player_id
  JOIN public.players p ON p.id = cp.player_id
  WHERE ml.status = 'open'
    AND cp.club_id = ml.seller_club_id
    AND cp.is_reserved
    AND (_position IS NULL OR p.position = _position)
    AND (_rarity IS NULL OR p.rarity = _rarity)
    AND (_min_overall IS NULL OR p.overall >= _min_overall)
    AND (_max_overall IS NULL OR p.overall <= _max_overall)
    AND (_max_price_cents IS NULL OR ml.price_cents <= _max_price_cents)
  ORDER BY ml.created_at DESC, ml.id;
END;
$$;

CREATE OR REPLACE FUNCTION public.create_market_listing(
  _club_player_id uuid,
  _price_cents integer
)
RETURNS TABLE(
  listing_id uuid,
  status public.market_listing_status,
  club_player_id uuid,
  price_cents integer,
  is_reserved boolean,
  idempotent boolean
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  _uid uuid := auth.uid();
  _club public.clubs%ROWTYPE;
  _card public.club_players%ROWTYPE;
  _listing public.market_listings%ROWTYPE;
  _roster_size integer;
BEGIN
  PERFORM public._expire_transfer_offers(pg_catalog.now());

  IF _uid IS NULL THEN
    RAISE EXCEPTION 'unauthenticated';
  END IF;
  IF NOT public.is_approved_user(_uid) THEN
    RAISE EXCEPTION 'profile_not_approved';
  END IF;
  IF _price_cents < 1 OR _price_cents > 10000 THEN
    RAISE EXCEPTION 'invalid_price';
  END IF;

  SELECT * INTO _club
  FROM public.clubs c
  WHERE c.owner_id = _uid
  FOR UPDATE;
  IF _club.id IS NULL THEN
    RAISE EXCEPTION 'club_not_found';
  END IF;

  SELECT * INTO _card
  FROM public.club_players cp
  WHERE cp.id = _club_player_id
  FOR UPDATE;
  IF _card.id IS NULL OR _card.club_id <> _club.id THEN
    RAISE EXCEPTION 'player_not_owned';
  END IF;
  IF EXISTS (
    SELECT 1 FROM public.system_market_stock sms
    WHERE sms.club_player_id = _card.id
  ) THEN
    RAISE EXCEPTION 'player_not_owned';
  END IF;
  IF EXISTS (
    SELECT 1 FROM public.market_listings ml
    WHERE ml.club_player_id = _card.id AND ml.status = 'open'
  ) THEN
    RAISE EXCEPTION 'player_already_listed';
  END IF;
  IF EXISTS (
    SELECT 1
    FROM public.transfer_offer_items toi
    JOIN public.transfer_offers o ON o.id = toi.offer_id
    WHERE toi.club_player_id = _card.id AND o.status = 'pending'
  ) THEN
    RAISE EXCEPTION 'player_in_pending_offer';
  END IF;
  IF _card.is_reserved THEN
    RAISE EXCEPTION 'player_reserved';
  END IF;

  SELECT pg_catalog.count(*)::integer INTO _roster_size
  FROM public.club_players cp
  WHERE cp.club_id = _club.id;
  IF _roster_size <= 5 THEN
    RAISE EXCEPTION 'roster_minimum';
  END IF;

  INSERT INTO public.market_listings(seller_club_id, club_player_id, price_cents, status)
  VALUES (_club.id, _card.id, _price_cents, 'open')
  RETURNING * INTO _listing;

  UPDATE public.club_players
  SET is_reserved = true
  WHERE id = _card.id;

  RETURN QUERY SELECT
    _listing.id,
    _listing.status,
    _card.id,
    _listing.price_cents,
    true,
    false;
END;
$$;

CREATE OR REPLACE FUNCTION public.cancel_market_listing(_listing_id uuid)
RETURNS TABLE(
  listing_id uuid,
  status public.market_listing_status,
  club_player_id uuid,
  price_cents integer,
  is_reserved boolean,
  idempotent boolean
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  _uid uuid := auth.uid();
  _club_id uuid;
  _listing public.market_listings%ROWTYPE;
BEGIN
  IF _uid IS NULL THEN
    RAISE EXCEPTION 'unauthenticated';
  END IF;
  IF NOT public.is_approved_user(_uid) THEN
    RAISE EXCEPTION 'profile_not_approved';
  END IF;

  SELECT c.id INTO _club_id
  FROM public.clubs c
  WHERE c.owner_id = _uid;
  IF _club_id IS NULL THEN
    RAISE EXCEPTION 'club_not_found';
  END IF;

  SELECT * INTO _listing
  FROM public.market_listings ml
  WHERE ml.id = _listing_id
  FOR UPDATE;
  IF _listing.id IS NULL THEN
    RAISE EXCEPTION 'listing_not_found';
  END IF;
  IF _listing.seller_club_id <> _club_id THEN
    RAISE EXCEPTION 'listing_not_found';
  END IF;
  IF _listing.status = 'cancelled' THEN
    RETURN QUERY SELECT
      _listing.id, _listing.status, _listing.club_player_id,
      _listing.price_cents, false, true;
    RETURN;
  END IF;
  IF _listing.status = 'sold' THEN
    RAISE EXCEPTION 'listing_not_open';
  END IF;
  IF _listing.status <> 'open' THEN
    RAISE EXCEPTION 'listing_not_open';
  END IF;

  PERFORM 1 FROM public.club_players cp
  WHERE cp.id = _listing.club_player_id
  FOR UPDATE;

  UPDATE public.market_listings
  SET status = 'cancelled', closed_at = pg_catalog.now()
  WHERE id = _listing.id
  RETURNING * INTO _listing;

  UPDATE public.club_players cp
  SET is_reserved = false
  WHERE cp.id = _listing.club_player_id
    AND NOT EXISTS (
      SELECT 1
      FROM public.transfer_offer_items toi
      JOIN public.transfer_offers o ON o.id = toi.offer_id
      WHERE toi.club_player_id = cp.id AND o.status = 'pending'
    );

  RETURN QUERY SELECT
    _listing.id, _listing.status, _listing.club_player_id,
    _listing.price_cents, false, false;
END;
$$;

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

  -- Stable lock chain: listing, card, then both clubs ordered by UUID.
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

  SELECT * INTO _buyer FROM public.clubs c WHERE c.id = _buyer_id;
  SELECT * INTO _seller FROM public.clubs c WHERE c.id = _listing.seller_club_id;
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
    WHERE toi.club_player_id = _card.id AND o.status = 'pending'
  ) THEN
    RAISE EXCEPTION 'player_in_pending_offer';
  END IF;

  SELECT pg_catalog.count(*)::integer INTO _buyer_roster
  FROM public.club_players cp WHERE cp.club_id = _buyer.id;
  SELECT pg_catalog.count(*)::integer INTO _seller_roster
  FROM public.club_players cp WHERE cp.club_id = _seller.id;

  IF _buyer_roster >= 15 THEN
    RAISE EXCEPTION 'roster_maximum';
  END IF;
  IF _seller_roster <= 5 THEN
    RAISE EXCEPTION 'roster_minimum';
  END IF;
  IF _buyer.balance_cents < _listing.price_cents THEN
    RAISE EXCEPTION 'insufficient_balance';
  END IF;
  IF _seller.balance_cents + _listing.price_cents > 10000 THEN
    RAISE EXCEPTION 'wallet_balance_cap_exceeded';
  END IF;

  _buyer_balance := public._debit_wallet(
    _buyer.id, _listing.price_cents, 'market_purchase',
    'market_listings', _listing.id, 'compra P2P'
  );
  _seller_balance := public._credit_wallet(
    _seller.id, _listing.price_cents, 'market_sale',
    'market_listings', _listing.id, 'venda P2P'
  );

  UPDATE public.club_players
  SET club_id = _buyer.id,
      acquired_at = pg_catalog.now(),
      is_reserved = false
  WHERE id = _card.id;

  UPDATE public.market_listings
  SET status = 'sold', closed_at = pg_catalog.now()
  WHERE id = _listing.id
  RETURNING * INTO _listing;

  RETURN QUERY SELECT
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

CREATE OR REPLACE FUNCTION public.list_trade_targets()
RETURNS TABLE(
  club_id uuid,
  name text,
  abbreviation text,
  roster_size integer
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  _uid uuid := auth.uid();
  _my_club_id uuid;
BEGIN
  IF _uid IS NULL THEN RAISE EXCEPTION 'unauthenticated'; END IF;
  IF NOT public.is_approved_user(_uid) THEN RAISE EXCEPTION 'profile_not_approved'; END IF;
  SELECT c.id INTO _my_club_id FROM public.clubs c WHERE c.owner_id = _uid;
  IF _my_club_id IS NULL THEN RAISE EXCEPTION 'club_not_found'; END IF;

  RETURN QUERY
  SELECT c.id, c.name, c.abbreviation, pg_catalog.count(cp.id)::integer
  FROM public.clubs c
  LEFT JOIN public.club_players cp ON cp.club_id = c.id
  WHERE c.id <> _my_club_id
    AND c.is_active
  GROUP BY c.id, c.name, c.abbreviation
  ORDER BY c.name, c.id;
END;
$$;

CREATE OR REPLACE FUNCTION public.get_trade_target_roster(_club_id uuid)
RETURNS TABLE(
  club_player_id uuid,
  player_id uuid,
  player_name text,
  "position" public.player_position,
  rarity public.player_rarity,
  sector public.player_sector,
  overall smallint,
  velocity smallint,
  finishing smallint,
  passing smallint,
  dribbling smallint,
  defending smallint,
  physical smallint,
  goalkeeping smallint,
  reference_value_cents integer
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  _uid uuid := auth.uid();
  _my_club_id uuid;
BEGIN
  PERFORM public._expire_transfer_offers(pg_catalog.now());
  IF _uid IS NULL THEN RAISE EXCEPTION 'unauthenticated'; END IF;
  IF NOT public.is_approved_user(_uid) THEN RAISE EXCEPTION 'profile_not_approved'; END IF;
  SELECT c.id INTO _my_club_id FROM public.clubs c WHERE c.owner_id = _uid;
  IF _my_club_id IS NULL THEN RAISE EXCEPTION 'club_not_found'; END IF;
  IF _club_id = _my_club_id OR NOT EXISTS (
    SELECT 1 FROM public.clubs c WHERE c.id = _club_id AND c.is_active
  ) THEN
    RAISE EXCEPTION 'club_not_found';
  END IF;

  RETURN QUERY
  SELECT
    cp.id, p.id, p.name, p.position, p.rarity, p.sector, p.overall,
    p.velocity, p.finishing, p.passing, p.dribbling,
    p.defending, p.physical, p.goalkeeping, p.reference_value_cents
  FROM public.club_players cp
  JOIN public.players p ON p.id = cp.player_id
  WHERE cp.club_id = _club_id
    AND NOT cp.is_reserved
    AND NOT EXISTS (
      SELECT 1 FROM public.market_listings ml
      WHERE ml.club_player_id = cp.id AND ml.status = 'open'
    )
    AND NOT EXISTS (
      SELECT 1
      FROM public.transfer_offer_items toi
      JOIN public.transfer_offers o ON o.id = toi.offer_id
      WHERE toi.club_player_id = cp.id AND o.status = 'pending'
    )
  ORDER BY p.name, cp.id;
END;
$$;

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

  IF _uid IS NULL THEN RAISE EXCEPTION 'unauthenticated'; END IF;
  IF NOT public.is_approved_user(_uid) THEN RAISE EXCEPTION 'profile_not_approved'; END IF;
  IF _cash_cents < 0 OR _cash_cents > 10000 THEN RAISE EXCEPTION 'invalid_cash'; END IF;
  IF _expires_at <= pg_catalog.now() THEN RAISE EXCEPTION 'offer_expired'; END IF;
  IF _from_count > 5 OR _to_count > 5 THEN RAISE EXCEPTION 'invalid_offer_size'; END IF;
  IF _from_count = 0 AND _to_count = 0 AND _cash_cents = 0 THEN
    RAISE EXCEPTION 'invalid_offer_empty';
  END IF;
  IF (SELECT pg_catalog.count(DISTINCT u.id) FROM unnest(_from_ids) AS u(id)) <> _from_count THEN
    RAISE EXCEPTION 'duplicate_player';
  END IF;
  IF (SELECT pg_catalog.count(DISTINCT u.id) FROM unnest(_to_ids) AS u(id)) <> _to_count THEN
    RAISE EXCEPTION 'duplicate_player';
  END IF;
  IF EXISTS (
    SELECT 1
    FROM unnest(_from_ids) AS f(id)
    JOIN unnest(_to_ids) AS t(id) ON t.id = f.id
  ) THEN
    RAISE EXCEPTION 'duplicate_player';
  END IF;

  SELECT * INTO _from_club FROM public.clubs c WHERE c.owner_id = _uid;
  IF _from_club.id IS NULL THEN RAISE EXCEPTION 'club_not_found'; END IF;
  IF _from_club.id = _to_club_id THEN RAISE EXCEPTION 'invalid_target_club'; END IF;
  SELECT * INTO _to_club FROM public.clubs c WHERE c.id = _to_club_id AND c.is_active;
  IF _to_club.id IS NULL THEN RAISE EXCEPTION 'club_not_found'; END IF;
  _from_club_id := _from_club.id;
  _target_club_id := _to_club.id;

  -- Both clubs are locked in UUID order; all cards follow in UUID order.
  PERFORM 1 FROM public.clubs c
  WHERE c.id IN (_from_club_id, _target_club_id)
  ORDER BY c.id
  FOR UPDATE;
  SELECT * INTO _from_club FROM public.clubs c WHERE c.id = _from_club_id;
  SELECT * INTO _to_club FROM public.clubs c WHERE c.id = _target_club_id;

  _all_ids := _from_ids || _to_ids;
  PERFORM 1 FROM public.club_players cp
  WHERE cp.id = ANY(_all_ids)
  ORDER BY cp.id
  FOR UPDATE;

  IF (SELECT pg_catalog.count(*) FROM public.club_players cp
      WHERE cp.id = ANY(_from_ids) AND cp.club_id = _from_club.id) <> _from_count THEN
    RAISE EXCEPTION 'player_not_owned';
  END IF;
  IF (SELECT pg_catalog.count(*) FROM public.club_players cp
      WHERE cp.id = ANY(_to_ids) AND cp.club_id = _to_club.id) <> _to_count THEN
    RAISE EXCEPTION 'player_not_owned';
  END IF;
  IF EXISTS (
    SELECT 1 FROM public.club_players cp
    WHERE cp.id = ANY(_all_ids) AND cp.is_reserved
  ) THEN
    RAISE EXCEPTION 'player_reserved';
  END IF;
  IF EXISTS (
    SELECT 1 FROM public.market_listings ml
    WHERE ml.club_player_id = ANY(_all_ids) AND ml.status = 'open'
  ) THEN
    RAISE EXCEPTION 'player_already_listed';
  END IF;
  IF EXISTS (
    SELECT 1
    FROM public.transfer_offer_items toi
    JOIN public.transfer_offers o ON o.id = toi.offer_id
    WHERE toi.club_player_id = ANY(_all_ids) AND o.status = 'pending'
  ) THEN
    RAISE EXCEPTION 'player_in_pending_offer';
  END IF;

  SELECT pg_catalog.count(*)::integer INTO _from_roster
  FROM public.club_players cp WHERE cp.club_id = _from_club.id;
  SELECT pg_catalog.count(*)::integer INTO _to_roster
  FROM public.club_players cp WHERE cp.club_id = _to_club.id;
  IF _from_roster - _from_count + _to_count NOT BETWEEN 5 AND 15 THEN
    RAISE EXCEPTION '%', CASE
      WHEN _from_roster - _from_count + _to_count < 5 THEN 'roster_minimum'
      ELSE 'roster_maximum'
    END;
  END IF;
  IF _to_roster - _to_count + _from_count NOT BETWEEN 5 AND 15 THEN
    RAISE EXCEPTION '%', CASE
      WHEN _to_roster - _to_count + _from_count < 5 THEN 'roster_minimum'
      ELSE 'roster_maximum'
    END;
  END IF;
  IF _from_club.balance_cents < _cash_cents THEN RAISE EXCEPTION 'insufficient_balance'; END IF;
  IF _to_club.balance_cents + _cash_cents > 10000 THEN
    RAISE EXCEPTION 'wallet_balance_cap_exceeded';
  END IF;

  INSERT INTO public.transfer_offers(
    from_club_id, to_club_id, cash_cents, status, expires_at
  ) VALUES (
    _from_club.id, _to_club.id, _cash_cents, 'pending', _expires_at
  ) RETURNING * INTO _offer;

  INSERT INTO public.transfer_offer_items(offer_id, club_player_id, side)
  SELECT _offer.id, u.club_player_id, 'from'
  FROM unnest(_from_ids) AS u(club_player_id);
  INSERT INTO public.transfer_offer_items(offer_id, club_player_id, side)
  SELECT _offer.id, u.club_player_id, 'to'
  FROM unnest(_to_ids) AS u(club_player_id);

  UPDATE public.club_players
  SET is_reserved = true
  WHERE id = ANY(_all_ids);

  RETURN QUERY SELECT
    _offer.id, _offer.status, _offer.expires_at,
    _from_count + _to_count, false;
END;
$$;

CREATE OR REPLACE FUNCTION public.list_my_transfer_offers()
RETURNS TABLE(
  offer_id uuid,
  direction text,
  status public.transfer_offer_status,
  from_club jsonb,
  to_club jsonb,
  cash_cents integer,
  created_at timestamptz,
  expires_at timestamptz,
  resolved_at timestamptz,
  from_cards jsonb,
  to_cards jsonb,
  can_accept boolean,
  can_reject boolean,
  can_cancel boolean
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  _uid uuid := auth.uid();
  _club_id uuid;
BEGIN
  PERFORM public._expire_transfer_offers(pg_catalog.now());
  IF _uid IS NULL THEN RAISE EXCEPTION 'unauthenticated'; END IF;
  IF NOT public.is_approved_user(_uid) THEN RAISE EXCEPTION 'profile_not_approved'; END IF;
  SELECT c.id INTO _club_id FROM public.clubs c WHERE c.owner_id = _uid;
  IF _club_id IS NULL THEN RAISE EXCEPTION 'club_not_found'; END IF;

  RETURN QUERY
  SELECT
    o.id,
    CASE WHEN o.to_club_id = _club_id THEN 'incoming' ELSE 'outgoing' END,
    o.status,
    pg_catalog.jsonb_build_object(
      'id', fc.id, 'name', fc.name, 'abbreviation', fc.abbreviation
    ),
    pg_catalog.jsonb_build_object(
      'id', tc.id, 'name', tc.name, 'abbreviation', tc.abbreviation
    ),
    o.cash_cents,
    o.created_at,
    o.expires_at,
    o.resolved_at,
    COALESCE((
      SELECT pg_catalog.jsonb_agg(
        pg_catalog.jsonb_build_object(
          'club_player_id', cp.id,
          'player_id', p.id,
          'player_name', p.name,
          'position', p.position,
          'rarity', p.rarity,
          'sector', p.sector,
          'overall', p.overall,
          'velocity', p.velocity,
          'finishing', p.finishing,
          'passing', p.passing,
          'dribbling', p.dribbling,
          'defending', p.defending,
          'physical', p.physical,
          'goalkeeping', p.goalkeeping,
          'reference_value_cents', p.reference_value_cents
        ) ORDER BY p.name, cp.id
      )
      FROM public.transfer_offer_items toi
      JOIN public.club_players cp ON cp.id = toi.club_player_id
      JOIN public.players p ON p.id = cp.player_id
      WHERE toi.offer_id = o.id AND toi.side = 'from'
    ), '[]'::jsonb),
    COALESCE((
      SELECT pg_catalog.jsonb_agg(
        pg_catalog.jsonb_build_object(
          'club_player_id', cp.id,
          'player_id', p.id,
          'player_name', p.name,
          'position', p.position,
          'rarity', p.rarity,
          'sector', p.sector,
          'overall', p.overall,
          'velocity', p.velocity,
          'finishing', p.finishing,
          'passing', p.passing,
          'dribbling', p.dribbling,
          'defending', p.defending,
          'physical', p.physical,
          'goalkeeping', p.goalkeeping,
          'reference_value_cents', p.reference_value_cents
        ) ORDER BY p.name, cp.id
      )
      FROM public.transfer_offer_items toi
      JOIN public.club_players cp ON cp.id = toi.club_player_id
      JOIN public.players p ON p.id = cp.player_id
      WHERE toi.offer_id = o.id AND toi.side = 'to'
    ), '[]'::jsonb),
    o.status = 'pending' AND o.expires_at > pg_catalog.now() AND o.to_club_id = _club_id,
    o.status = 'pending' AND o.expires_at > pg_catalog.now() AND o.to_club_id = _club_id,
    o.status = 'pending' AND o.expires_at > pg_catalog.now() AND o.from_club_id = _club_id
  FROM public.transfer_offers o
  JOIN public.clubs fc ON fc.id = o.from_club_id
  JOIN public.clubs tc ON tc.id = o.to_club_id
  WHERE _club_id IN (o.from_club_id, o.to_club_id)
  ORDER BY o.created_at DESC, o.id;
END;
$$;

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
  IF _uid IS NULL THEN RAISE EXCEPTION 'unauthenticated'; END IF;
  IF NOT public.is_approved_user(_uid) THEN RAISE EXCEPTION 'profile_not_approved'; END IF;
  SELECT c.id INTO _caller_club_id FROM public.clubs c WHERE c.owner_id = _uid;
  IF _caller_club_id IS NULL THEN RAISE EXCEPTION 'club_not_found'; END IF;

  SELECT * INTO _offer
  FROM public.transfer_offers o
  WHERE o.id = _offer_id
  FOR UPDATE;
  IF _offer.id IS NULL THEN RAISE EXCEPTION 'offer_not_found'; END IF;
  IF _offer.to_club_id <> _caller_club_id THEN RAISE EXCEPTION 'offer_not_recipient'; END IF;
  IF _offer.status = 'accepted' THEN
    RETURN QUERY SELECT _offer.id, _offer.status, _offer.resolved_at, true;
    RETURN;
  END IF;
  IF _offer.status = 'expired' OR _offer.expires_at <= pg_catalog.now() THEN
    RAISE EXCEPTION 'offer_expired';
  END IF;
  IF _offer.status <> 'pending' THEN RAISE EXCEPTION 'offer_not_pending'; END IF;

  PERFORM 1 FROM public.clubs c
  WHERE c.id IN (_offer.from_club_id, _offer.to_club_id)
  ORDER BY c.id
  FOR UPDATE;
  SELECT * INTO _from_club FROM public.clubs c WHERE c.id = _offer.from_club_id;
  SELECT * INTO _to_club FROM public.clubs c WHERE c.id = _offer.to_club_id;

  PERFORM 1
  FROM public.club_players cp
  JOIN public.transfer_offer_items toi ON toi.club_player_id = cp.id
  WHERE toi.offer_id = _offer.id
  ORDER BY cp.id
  FOR UPDATE OF cp;

  SELECT pg_catalog.count(*)::integer INTO _from_count
  FROM public.transfer_offer_items toi WHERE toi.offer_id = _offer.id AND toi.side = 'from';
  SELECT pg_catalog.count(*)::integer INTO _to_count
  FROM public.transfer_offer_items toi WHERE toi.offer_id = _offer.id AND toi.side = 'to';

  IF EXISTS (
    SELECT 1
    FROM public.transfer_offer_items toi
    LEFT JOIN public.club_players cp ON cp.id = toi.club_player_id
    WHERE toi.offer_id = _offer.id
      AND (
        cp.id IS NULL
        OR NOT cp.is_reserved
        OR (toi.side = 'from' AND cp.club_id <> _offer.from_club_id)
        OR (toi.side = 'to' AND cp.club_id <> _offer.to_club_id)
      )
  ) THEN
    RAISE EXCEPTION 'player_not_owned';
  END IF;
  IF EXISTS (
    SELECT 1
    FROM public.transfer_offer_items toi
    JOIN public.market_listings ml ON ml.club_player_id = toi.club_player_id
    WHERE toi.offer_id = _offer.id AND ml.status = 'open'
  ) THEN
    RAISE EXCEPTION 'player_already_listed';
  END IF;

  SELECT pg_catalog.count(*)::integer INTO _from_roster
  FROM public.club_players cp WHERE cp.club_id = _from_club.id;
  SELECT pg_catalog.count(*)::integer INTO _to_roster
  FROM public.club_players cp WHERE cp.club_id = _to_club.id;
  IF _from_roster - _from_count + _to_count NOT BETWEEN 5 AND 15 THEN
    RAISE EXCEPTION '%', CASE
      WHEN _from_roster - _from_count + _to_count < 5 THEN 'roster_minimum'
      ELSE 'roster_maximum'
    END;
  END IF;
  IF _to_roster - _to_count + _from_count NOT BETWEEN 5 AND 15 THEN
    RAISE EXCEPTION '%', CASE
      WHEN _to_roster - _to_count + _from_count < 5 THEN 'roster_minimum'
      ELSE 'roster_maximum'
    END;
  END IF;
  IF _from_club.balance_cents < _offer.cash_cents THEN RAISE EXCEPTION 'insufficient_balance'; END IF;
  IF _to_club.balance_cents + _offer.cash_cents > 10000 THEN
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
      _offer.from_club_id, _offer.cash_cents, 'transfer_cash',
      'transfer_offers', _offer.id, 'dinheiro em troca P2P'
    );
    PERFORM public._credit_wallet(
      _offer.to_club_id, _offer.cash_cents, 'transfer_cash',
      'transfer_offers', _offer.id, 'dinheiro recebido em troca P2P'
    );
  END IF;

  _resolved_at := pg_catalog.now();
  UPDATE public.transfer_offers
  SET status = 'accepted', resolved_at = _resolved_at
  WHERE id = _offer.id
  RETURNING * INTO _offer;

  RETURN QUERY SELECT _offer.id, _offer.status, _offer.resolved_at, false;
END;
$$;

CREATE OR REPLACE FUNCTION public.reject_transfer_offer(_offer_id uuid)
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
  _club_id uuid;
  _offer public.transfer_offers%ROWTYPE;
BEGIN
  IF _uid IS NULL THEN RAISE EXCEPTION 'unauthenticated'; END IF;
  IF NOT public.is_approved_user(_uid) THEN RAISE EXCEPTION 'profile_not_approved'; END IF;
  SELECT c.id INTO _club_id FROM public.clubs c WHERE c.owner_id = _uid;
  IF _club_id IS NULL THEN RAISE EXCEPTION 'club_not_found'; END IF;
  SELECT * INTO _offer FROM public.transfer_offers o WHERE o.id = _offer_id FOR UPDATE;
  IF _offer.id IS NULL THEN RAISE EXCEPTION 'offer_not_found'; END IF;
  IF _offer.to_club_id <> _club_id THEN RAISE EXCEPTION 'offer_not_recipient'; END IF;
  IF _offer.status = 'rejected' THEN
    RETURN QUERY SELECT _offer.id, _offer.status, _offer.resolved_at, true;
    RETURN;
  END IF;
  IF _offer.status <> 'pending' THEN RAISE EXCEPTION 'offer_not_pending'; END IF;

  PERFORM 1
  FROM public.club_players cp
  JOIN public.transfer_offer_items toi ON toi.club_player_id = cp.id
  WHERE toi.offer_id = _offer.id
  ORDER BY cp.id
  FOR UPDATE OF cp;
  UPDATE public.transfer_offers
  SET status = 'rejected', resolved_at = pg_catalog.now()
  WHERE id = _offer.id
  RETURNING * INTO _offer;
  PERFORM public._release_transfer_offer_cards(_offer.id);
  RETURN QUERY SELECT _offer.id, _offer.status, _offer.resolved_at, false;
END;
$$;

CREATE OR REPLACE FUNCTION public.cancel_transfer_offer(_offer_id uuid)
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
  _club_id uuid;
  _offer public.transfer_offers%ROWTYPE;
BEGIN
  IF _uid IS NULL THEN RAISE EXCEPTION 'unauthenticated'; END IF;
  IF NOT public.is_approved_user(_uid) THEN RAISE EXCEPTION 'profile_not_approved'; END IF;
  SELECT c.id INTO _club_id FROM public.clubs c WHERE c.owner_id = _uid;
  IF _club_id IS NULL THEN RAISE EXCEPTION 'club_not_found'; END IF;
  SELECT * INTO _offer FROM public.transfer_offers o WHERE o.id = _offer_id FOR UPDATE;
  IF _offer.id IS NULL THEN RAISE EXCEPTION 'offer_not_found'; END IF;
  IF _offer.from_club_id <> _club_id THEN RAISE EXCEPTION 'offer_not_sender'; END IF;
  IF _offer.status = 'cancelled' THEN
    RETURN QUERY SELECT _offer.id, _offer.status, _offer.resolved_at, true;
    RETURN;
  END IF;
  IF _offer.status <> 'pending' THEN RAISE EXCEPTION 'offer_not_pending'; END IF;

  PERFORM 1
  FROM public.club_players cp
  JOIN public.transfer_offer_items toi ON toi.club_player_id = cp.id
  WHERE toi.offer_id = _offer.id
  ORDER BY cp.id
  FOR UPDATE OF cp;
  UPDATE public.transfer_offers
  SET status = 'cancelled', resolved_at = pg_catalog.now()
  WHERE id = _offer.id
  RETURNING * INTO _offer;
  PERFORM public._release_transfer_offer_cards(_offer.id);
  RETURN QUERY SELECT _offer.id, _offer.status, _offer.resolved_at, false;
END;
$$;

-- Reinforce RPC-only writes. Reads remain protected by the existing
-- approved-only RLS policies.
REVOKE INSERT, UPDATE, DELETE, TRUNCATE, REFERENCES, TRIGGER ON TABLE
  public.market_listings,
  public.transfer_offers,
  public.transfer_offer_items,
  public.club_players,
  public.clubs,
  public.wallet_transactions
FROM authenticated, anon;

REVOKE ALL ON FUNCTION public.list_market_listings(
  public.player_position, public.player_rarity, integer, integer, integer
) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.create_market_listing(uuid, integer) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.cancel_market_listing(uuid) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.buy_market_listing(uuid) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.create_transfer_offer(uuid, uuid[], uuid[], integer, timestamptz)
  FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.list_my_transfer_offers() FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.accept_transfer_offer(uuid) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.reject_transfer_offer(uuid) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.cancel_transfer_offer(uuid) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.list_trade_targets() FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.get_trade_target_roster(uuid) FROM PUBLIC, anon;

GRANT EXECUTE ON FUNCTION public.list_market_listings(
  public.player_position, public.player_rarity, integer, integer, integer
) TO authenticated;
GRANT EXECUTE ON FUNCTION public.create_market_listing(uuid, integer) TO authenticated;
GRANT EXECUTE ON FUNCTION public.cancel_market_listing(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.buy_market_listing(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.create_transfer_offer(uuid, uuid[], uuid[], integer, timestamptz)
  TO authenticated;
GRANT EXECUTE ON FUNCTION public.list_my_transfer_offers() TO authenticated;
GRANT EXECUTE ON FUNCTION public.accept_transfer_offer(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.reject_transfer_offer(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.cancel_transfer_offer(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.list_trade_targets() TO authenticated;
GRANT EXECUTE ON FUNCTION public.get_trade_target_roster(uuid) TO authenticated;
