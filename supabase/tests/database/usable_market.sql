-- Transactional contract test for the usable system/P2P market.
-- Apply 20260710120000_usable_market.sql before running this file manually.

BEGIN;

DO $$
DECLARE
  _league_id uuid;
  _badge_id uuid;
  _users uuid[] := ARRAY[
    '00000000-0000-0000-0000-000000051001'::uuid,
    '00000000-0000-0000-0000-000000051002'::uuid,
    '00000000-0000-0000-0000-000000051003'::uuid,
    '00000000-0000-0000-0000-000000051004'::uuid,
    '00000000-0000-0000-0000-000000051005'::uuid,
    '00000000-0000-0000-0000-000000051006'::uuid
  ];
  _clubs uuid[] := ARRAY[
    '00000000-0000-0000-0000-000000051101'::uuid,
    '00000000-0000-0000-0000-000000051102'::uuid,
    '00000000-0000-0000-0000-000000051103'::uuid,
    '00000000-0000-0000-0000-000000051104'::uuid,
    '00000000-0000-0000-0000-000000051105'::uuid,
    '00000000-0000-0000-0000-000000051106'::uuid
  ];
  _seller uuid := '00000000-0000-0000-0000-000000051101'::uuid;
  _buyer uuid := '00000000-0000-0000-0000-000000051102'::uuid;
  _target uuid := '00000000-0000-0000-0000-000000051103'::uuid;
  _minimum uuid := '00000000-0000-0000-0000-000000051104'::uuid;
  _maximum uuid := '00000000-0000-0000-0000-000000051105'::uuid;
  _training uuid := '00000000-0000-0000-0000-000000051106'::uuid;
  _seller_cards uuid[] := ARRAY[]::uuid[];
  _buyer_cards uuid[] := ARRAY[]::uuid[];
  _target_cards uuid[] := ARRAY[]::uuid[];
  _minimum_cards uuid[] := ARRAY[]::uuid[];
  _maximum_cards uuid[] := ARRAY[]::uuid[];
  _training_cards uuid[] := ARRAY[]::uuid[];
  _system_card uuid;
  _card uuid;
  _listing uuid;
  _offer uuid;
  _price integer;
  _before_a integer;
  _before_b integer;
  _after_a integer;
  _after_b integer;
  _ledger_before integer;
  _ledger_after integer;
  _count integer;
  _message text;
  _result record;
  _i integer;
BEGIN
  SELECT l.id INTO _league_id FROM public.leagues l WHERE l.slug = 'bagreleirao';
  SELECT b.id INTO _badge_id
  FROM public.club_badges b WHERE b.is_active ORDER BY b.sort_order, b.code LIMIT 1;
  IF _league_id IS NULL OR _badge_id IS NULL THEN
    RAISE EXCEPTION 'test_setup_failed: league or badge missing';
  END IF;

  UPDATE public.leagues SET status = 'setup', max_clubs = 1000 WHERE id = _league_id;

  FOR _i IN 1..6 LOOP
    INSERT INTO auth.users(
      id, instance_id, aud, role, email, encrypted_password, email_confirmed_at,
      raw_app_meta_data, raw_user_meta_data, created_at, updated_at
    ) VALUES (
      _users[_i],
      '00000000-0000-0000-0000-000000000000',
      'authenticated', 'authenticated',
      'usable-market-' || _i::text || '@example.test', 'test-password', pg_catalog.now(),
      '{"provider":"email","providers":["email"]}'::jsonb,
      pg_catalog.jsonb_build_object('username', 'umkt' || _i::text),
      pg_catalog.now(), pg_catalog.now()
    );
  END LOOP;
  UPDATE public.profiles SET status = 'approved' WHERE id = ANY(_users);

  INSERT INTO public.clubs(
    id, league_id, owner_id, name, normalized_name, abbreviation, badge_id, balance_cents
  ) VALUES
    (_clubs[1], _league_id, _users[1], 'UM Seller', public.normalize_club_name('UM Seller'), 'UMS', _badge_id, 1000),
    (_clubs[2], _league_id, _users[2], 'UM Buyer', public.normalize_club_name('UM Buyer'), 'UMB', _badge_id, 8000),
    (_clubs[3], _league_id, _users[3], 'UM Target', public.normalize_club_name('UM Target'), 'UMT', _badge_id, 1000),
    (_clubs[4], _league_id, _users[4], 'UM Minimum', public.normalize_club_name('UM Minimum'), 'UMN', _badge_id, 1000),
    (_clubs[5], _league_id, _users[5], 'UM Maximum', public.normalize_club_name('UM Maximum'), 'UMX', _badge_id, 8000),
    (_clubs[6], _league_id, _users[6], 'UM Training', public.normalize_club_name('UM Training'), 'UMR', _badge_id, 1000);

  -- Player inserts create permanent system cards. Move the same rows to clubs.
  FOR _i IN 1..60 LOOP
    INSERT INTO public.players(
      code, name, position, rarity, sector, overall,
      velocity, finishing, passing, dribbling, defending, physical, goalkeeping,
      reference_value_cents
    ) VALUES (
      'BFUM-' || pg_catalog.lpad(_i::text, 3, '0'),
      'Usable Market Player ' || _i::text,
      (ARRAY['GK','DEF','MID','ATA'])[((_i - 1) % 4) + 1]::public.player_position,
      CASE WHEN _i <= 45 THEN 'peba'::public.player_rarity ELSE 'paia'::public.player_rarity END,
      'centro', 1,
      CASE WHEN _i % 4 = 1 THEN 44 ELSE 52 END,
      CASE WHEN _i % 4 = 0 THEN 57 ELSE 41 END,
      CASE WHEN _i % 4 = 3 THEN 58 ELSE 43 END,
      CASE WHEN _i % 4 = 3 THEN 56 ELSE 42 END,
      CASE WHEN _i % 4 = 2 THEN 58 ELSE 44 END,
      CASE WHEN _i % 4 = 2 THEN 55 ELSE 45 END,
      CASE WHEN _i % 4 = 1 THEN 60 ELSE 6 END,
      1
    );

    SELECT cp.id INTO _card
    FROM public.club_players cp
    JOIN public.players p ON p.id = cp.player_id
    WHERE p.code = 'BFUM-' || pg_catalog.lpad(_i::text, 3, '0');

    IF _i <= 8 THEN
      DELETE FROM public.system_market_stock WHERE club_player_id = _card;
      UPDATE public.club_players SET club_id = _seller WHERE id = _card;
      _seller_cards := _seller_cards || _card;
    ELSIF _i <= 16 THEN
      DELETE FROM public.system_market_stock WHERE club_player_id = _card;
      UPDATE public.club_players SET club_id = _buyer WHERE id = _card;
      _buyer_cards := _buyer_cards || _card;
    ELSIF _i <= 24 THEN
      DELETE FROM public.system_market_stock WHERE club_player_id = _card;
      UPDATE public.club_players SET club_id = _target WHERE id = _card;
      _target_cards := _target_cards || _card;
    ELSIF _i <= 29 THEN
      DELETE FROM public.system_market_stock WHERE club_player_id = _card;
      UPDATE public.club_players SET club_id = _minimum WHERE id = _card;
      _minimum_cards := _minimum_cards || _card;
    ELSIF _i <= 44 THEN
      DELETE FROM public.system_market_stock WHERE club_player_id = _card;
      UPDATE public.club_players SET club_id = _maximum WHERE id = _card;
      _maximum_cards := _maximum_cards || _card;
    ELSIF _i <= 50 THEN
      DELETE FROM public.system_market_stock WHERE club_player_id = _card;
      UPDATE public.club_players SET club_id = _training WHERE id = _card;
      _training_cards := _training_cards || _card;
    ELSIF _i = 51 THEN
      _system_card := _card;
    END IF;
  END LOOP;

  IF EXISTS (
    SELECT 1 FROM public.club_players cp
    WHERE (cp.club_id IS NULL) <> EXISTS (
      SELECT 1 FROM public.system_market_stock sms WHERE sms.club_player_id = cp.id
    )
  ) THEN
    RAISE EXCEPTION 'assertion_failed: permanent card/system stock invariant';
  END IF;

  -- Approved-only and RPC-only security.
  UPDATE public.profiles SET status = 'pending' WHERE id = _users[1];
  PERFORM pg_catalog.set_config('request.jwt.claim.sub', _users[1]::text, true);
  BEGIN
    PERFORM * FROM public.list_market_listings();
    RAISE EXCEPTION 'assertion_failed: pending profile listed market';
  EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS _message = MESSAGE_TEXT;
    IF _message <> 'profile_not_approved' THEN RAISE; END IF;
  END;
  UPDATE public.profiles SET status = 'approved' WHERE id = _users[1];

  BEGIN
    EXECUTE 'SET LOCAL ROLE authenticated';
    UPDATE public.market_listings SET price_cents = 1;
    EXECUTE 'RESET ROLE';
    RAISE EXCEPTION 'assertion_failed: direct market write succeeded';
  EXCEPTION WHEN insufficient_privilege THEN
    EXECUTE 'RESET ROLE';
  END;

  -- System purchase: ownership, balance, ledger and 100% reference price.
  PERFORM pg_catalog.set_config('request.jwt.claim.sub', _users[2]::text, true);
  SELECT p.reference_value_cents, c.balance_cents INTO _price, _before_a
  FROM public.club_players cp
  JOIN public.players p ON p.id = cp.player_id
  CROSS JOIN public.clubs c
  WHERE cp.id = _system_card AND c.id = _buyer;
  SELECT * INTO _result FROM public.buy_player_from_system(_system_card);
  IF _result.price_cents <> _price OR _result.balance_cents <> _before_a - _price THEN
    RAISE EXCEPTION 'assertion_failed: system purchase price/balance';
  END IF;
  IF (SELECT club_id FROM public.club_players WHERE id = _system_card) <> _buyer THEN
    RAISE EXCEPTION 'assertion_failed: system purchase ownership';
  END IF;
  IF NOT EXISTS (
    SELECT 1 FROM public.wallet_transactions wt
    WHERE wt.club_id = _buyer AND wt.kind = 'system_purchase'
      AND wt.amount_cents = -_price AND wt.reference_id = _system_card
  ) THEN RAISE EXCEPTION 'assertion_failed: system purchase ledger'; END IF;

  -- System sale: 50%, no deletion, minimum/maximum and reserved protections.
  UPDATE public.club_players SET is_reserved = true WHERE id = _system_card;
  BEGIN
    PERFORM * FROM public.sell_player_to_system(_system_card);
    RAISE EXCEPTION 'assertion_failed: reserved system sale';
  EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS _message = MESSAGE_TEXT;
    IF _message <> 'card_reserved' THEN RAISE; END IF;
  END;
  UPDATE public.club_players SET is_reserved = false WHERE id = _system_card;
  SELECT p.reference_value_cents, c.balance_cents INTO _price, _before_a
  FROM public.club_players cp JOIN public.players p ON p.id = cp.player_id
  JOIN public.clubs c ON c.id = cp.club_id WHERE cp.id = _system_card;
  _price := pg_catalog.floor(_price / 2.0)::integer;
  SELECT * INTO _result FROM public.sell_player_to_system(_system_card);
  IF _result.price_cents <> _price OR _result.balance_cents <> _before_a + _price THEN
    RAISE EXCEPTION 'assertion_failed: system sale price/balance';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM public.club_players WHERE id = _system_card AND club_id IS NULL) THEN
    RAISE EXCEPTION 'assertion_failed: system sale permanent card';
  END IF;

  PERFORM pg_catalog.set_config('request.jwt.claim.sub', _users[4]::text, true);
  BEGIN
    PERFORM * FROM public.sell_player_to_system(_minimum_cards[1]);
    RAISE EXCEPTION 'assertion_failed: five-card system sale';
  EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS _message = MESSAGE_TEXT;
    IF _message <> 'roster_minimum_reached' THEN RAISE; END IF;
  END;

  PERFORM pg_catalog.set_config('request.jwt.claim.sub', _users[5]::text, true);
  BEGIN
    PERFORM * FROM public.buy_player_from_system(_system_card);
    RAISE EXCEPTION 'assertion_failed: fifteen-card system purchase';
  EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS _message = MESSAGE_TEXT;
    IF _message <> 'roster_maximum_reached' THEN RAISE; END IF;
  END;

  -- Training: reserved protection, cost/ledger and America/Belem daily limit.
  PERFORM pg_catalog.set_config('request.jwt.claim.sub', _users[6]::text, true);
  UPDATE public.club_players SET is_reserved = true WHERE id = _training_cards[1];
  BEGIN
    PERFORM * FROM public.train_club_player(_training_cards[1], 'velocity');
    RAISE EXCEPTION 'assertion_failed: reserved card trained';
  EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS _message = MESSAGE_TEXT;
    IF _message <> 'card_reserved' THEN RAISE; END IF;
  END;
  UPDATE public.club_players SET is_reserved = false WHERE id = _training_cards[1];
  SELECT balance_cents INTO _before_a FROM public.clubs WHERE id = _training;
  SELECT * INTO _result FROM public.train_club_player(_training_cards[1], 'velocity');
  IF _result.cost_cents <> 25 OR _result.balance_cents <> _before_a - 25 THEN
    RAISE EXCEPTION 'assertion_failed: training cost';
  END IF;
  IF NOT EXISTS (
    SELECT 1 FROM public.wallet_transactions wt
    WHERE wt.club_id = _training AND wt.kind = 'training_cost'
      AND wt.reference_id = _result.session_id
  ) THEN RAISE EXCEPTION 'assertion_failed: training ledger'; END IF;
  BEGIN
    PERFORM * FROM public.train_club_player(_training_cards[2], 'passing');
    RAISE EXCEPTION 'assertion_failed: second America/Belem daily training';
  EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS _message = MESSAGE_TEXT;
    IF _message <> 'training_already_done_today' THEN RAISE; END IF;
  END;

  -- Listing reserve, duplicate block, cancellation release and idempotency.
  PERFORM pg_catalog.set_config('request.jwt.claim.sub', _users[1]::text, true);
  SELECT r.listing_id INTO _listing
  FROM public.create_market_listing(_seller_cards[1], 300) r;
  IF NOT (SELECT is_reserved FROM public.club_players WHERE id = _seller_cards[1]) THEN
    RAISE EXCEPTION 'assertion_failed: listing did not reserve card';
  END IF;
  BEGIN
    PERFORM * FROM public.create_market_listing(_seller_cards[1], 301);
    RAISE EXCEPTION 'assertion_failed: duplicate listing';
  EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS _message = MESSAGE_TEXT;
    IF _message <> 'player_already_listed' THEN RAISE; END IF;
  END;
  BEGIN
    PERFORM * FROM public.create_transfer_offer(
      _target, ARRAY[_seller_cards[1]], ARRAY[]::uuid[], 0,
      pg_catalog.now() + interval '1 hour'
    );
    RAISE EXCEPTION 'assertion_failed: listed card entered offer';
  EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS _message = MESSAGE_TEXT;
    IF _message NOT IN ('player_reserved', 'player_already_listed') THEN RAISE; END IF;
  END;
  SELECT * INTO _result FROM public.cancel_market_listing(_listing);
  IF _result.idempotent OR (SELECT is_reserved FROM public.club_players WHERE id = _seller_cards[1]) THEN
    RAISE EXCEPTION 'assertion_failed: cancellation did not release';
  END IF;
  SELECT * INTO _result FROM public.cancel_market_listing(_listing);
  IF NOT _result.idempotent THEN RAISE EXCEPTION 'assertion_failed: cancel not idempotent'; END IF;

  -- Minimum roster cannot advertise.
  PERFORM pg_catalog.set_config('request.jwt.claim.sub', _users[4]::text, true);
  BEGIN
    PERFORM * FROM public.create_market_listing(_minimum_cards[1], 100);
    RAISE EXCEPTION 'assertion_failed: minimum roster advertised';
  EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS _message = MESSAGE_TEXT;
    IF _message <> 'roster_minimum' THEN RAISE; END IF;
  END;

  -- P2P purchase: two balances, two ledgers, ownership and repeat safety.
  PERFORM pg_catalog.set_config('request.jwt.claim.sub', _users[1]::text, true);
  SELECT r.listing_id INTO _listing
  FROM public.create_market_listing(_seller_cards[1], 300) r;
  BEGIN
    PERFORM * FROM public.buy_market_listing(_listing);
    RAISE EXCEPTION 'assertion_failed: own listing purchase';
  EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS _message = MESSAGE_TEXT;
    IF _message <> 'cannot_buy_own_listing' THEN RAISE; END IF;
  END;
  SELECT balance_cents INTO _before_a FROM public.clubs WHERE id = _buyer;
  SELECT balance_cents INTO _before_b FROM public.clubs WHERE id = _seller;
  SELECT pg_catalog.count(*) INTO _ledger_before
  FROM public.wallet_transactions WHERE reference_table = 'market_listings' AND reference_id = _listing;
  PERFORM pg_catalog.set_config('request.jwt.claim.sub', _users[2]::text, true);
  SELECT * INTO _result FROM public.buy_market_listing(_listing);
  SELECT balance_cents INTO _after_a FROM public.clubs WHERE id = _buyer;
  SELECT balance_cents INTO _after_b FROM public.clubs WHERE id = _seller;
  IF _after_a <> _before_a - 300 OR _after_b <> _before_b + 300 THEN
    RAISE EXCEPTION 'assertion_failed: P2P balances';
  END IF;
  IF (SELECT club_id FROM public.club_players WHERE id = _seller_cards[1]) <> _buyer THEN
    RAISE EXCEPTION 'assertion_failed: P2P ownership';
  END IF;
  IF (SELECT pg_catalog.count(*) FROM public.wallet_transactions
      WHERE reference_table = 'market_listings' AND reference_id = _listing) <> _ledger_before + 2 THEN
    RAISE EXCEPTION 'assertion_failed: P2P ledgers';
  END IF;
  SELECT pg_catalog.count(*) INTO _ledger_before FROM public.wallet_transactions
  WHERE reference_table = 'market_listings' AND reference_id = _listing;
  BEGIN
    PERFORM * FROM public.buy_market_listing(_listing);
    RAISE EXCEPTION 'assertion_failed: repeated listing purchase';
  EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS _message = MESSAGE_TEXT;
    IF _message <> 'listing_not_open' THEN RAISE; END IF;
  END;
  SELECT pg_catalog.count(*) INTO _ledger_after FROM public.wallet_transactions
  WHERE reference_table = 'market_listings' AND reference_id = _listing;
  IF _ledger_after <> _ledger_before THEN RAISE EXCEPTION 'assertion_failed: duplicate P2P ledger'; END IF;

  -- Insufficient balance and maximum roster both roll back completely.
  PERFORM pg_catalog.set_config('request.jwt.claim.sub', _users[1]::text, true);
  SELECT r.listing_id INTO _listing FROM public.create_market_listing(_seller_cards[2], 1000) r;
  UPDATE public.clubs SET balance_cents = 0 WHERE id = _buyer;
  PERFORM pg_catalog.set_config('request.jwt.claim.sub', _users[2]::text, true);
  BEGIN
    PERFORM * FROM public.buy_market_listing(_listing);
    RAISE EXCEPTION 'assertion_failed: insufficient P2P balance';
  EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS _message = MESSAGE_TEXT;
    IF _message <> 'insufficient_balance' THEN RAISE; END IF;
  END;
  IF (SELECT club_id FROM public.club_players WHERE id = _seller_cards[2]) <> _seller THEN
    RAISE EXCEPTION 'assertion_failed: failed purchase transferred card';
  END IF;
  PERFORM pg_catalog.set_config('request.jwt.claim.sub', _users[1]::text, true);
  PERFORM * FROM public.cancel_market_listing(_listing);
  SELECT r.listing_id INTO _listing FROM public.create_market_listing(_seller_cards[2], 100) r;
  PERFORM pg_catalog.set_config('request.jwt.claim.sub', _users[5]::text, true);
  BEGIN
    PERFORM * FROM public.buy_market_listing(_listing);
    RAISE EXCEPTION 'assertion_failed: maximum roster P2P purchase';
  EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS _message = MESSAGE_TEXT;
    IF _message <> 'roster_maximum' THEN RAISE; END IF;
  END;
  PERFORM pg_catalog.set_config('request.jwt.claim.sub', _users[1]::text, true);
  PERFORM * FROM public.cancel_market_listing(_listing);

  -- Duplicate and wrong-club offer inputs are rejected before reservation.
  BEGIN
    PERFORM * FROM public.create_transfer_offer(
      _target, ARRAY[_seller_cards[3], _seller_cards[3]], ARRAY[]::uuid[], 0,
      pg_catalog.now() + interval '1 hour'
    );
    RAISE EXCEPTION 'assertion_failed: duplicate offer cards';
  EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS _message = MESSAGE_TEXT;
    IF _message <> 'duplicate_player' THEN RAISE; END IF;
  END;
  BEGIN
    PERFORM * FROM public.create_transfer_offer(
      _target, ARRAY[_buyer_cards[1]], ARRAY[]::uuid[], 0,
      pg_catalog.now() + interval '1 hour'
    );
    RAISE EXCEPTION 'assertion_failed: wrong-club offered card';
  EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS _message = MESSAGE_TEXT;
    IF _message <> 'player_not_owned' THEN RAISE; END IF;
  END;

  -- Reject releases all cards and is idempotent.
  SELECT r.offer_id INTO _offer FROM public.create_transfer_offer(
    _target, ARRAY[_seller_cards[3]], ARRAY[_target_cards[1]], 50,
    pg_catalog.now() + interval '1 hour'
  ) r;
  BEGIN
    PERFORM * FROM public.create_market_listing(_seller_cards[3], 250);
    RAISE EXCEPTION 'assertion_failed: offered card entered listing';
  EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS _message = MESSAGE_TEXT;
    IF _message <> 'player_in_pending_offer' THEN RAISE; END IF;
  END;
  IF NOT EXISTS (
    SELECT 1 FROM public.club_players WHERE id IN (_seller_cards[3], _target_cards[1]) AND is_reserved
    HAVING pg_catalog.count(*) = 2
  ) THEN RAISE EXCEPTION 'assertion_failed: offer reservation'; END IF;
  PERFORM pg_catalog.set_config('request.jwt.claim.sub', _users[2]::text, true);
  BEGIN
    PERFORM * FROM public.reject_transfer_offer(_offer);
    RAISE EXCEPTION 'assertion_failed: non-recipient rejected';
  EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS _message = MESSAGE_TEXT;
    IF _message <> 'offer_not_recipient' THEN RAISE; END IF;
  END;
  PERFORM pg_catalog.set_config('request.jwt.claim.sub', _users[3]::text, true);
  SELECT * INTO _result FROM public.reject_transfer_offer(_offer);
  IF EXISTS (SELECT 1 FROM public.club_players WHERE id IN (_seller_cards[3], _target_cards[1]) AND is_reserved) THEN
    RAISE EXCEPTION 'assertion_failed: reject did not release';
  END IF;
  SELECT * INTO _result FROM public.reject_transfer_offer(_offer);
  IF NOT _result.idempotent THEN RAISE EXCEPTION 'assertion_failed: reject not idempotent'; END IF;

  -- Sender cancellation and core expiration release every involved card.
  PERFORM pg_catalog.set_config('request.jwt.claim.sub', _users[1]::text, true);
  SELECT r.offer_id INTO _offer FROM public.create_transfer_offer(
    _target, ARRAY[_seller_cards[3]], ARRAY[_target_cards[1]], 0,
    pg_catalog.now() + interval '1 hour'
  ) r;
  SELECT * INTO _result FROM public.cancel_transfer_offer(_offer);
  IF EXISTS (SELECT 1 FROM public.club_players WHERE id IN (_seller_cards[3], _target_cards[1]) AND is_reserved) THEN
    RAISE EXCEPTION 'assertion_failed: cancel did not release';
  END IF;
  SELECT * INTO _result FROM public.cancel_transfer_offer(_offer);
  IF NOT _result.idempotent THEN RAISE EXCEPTION 'assertion_failed: offer cancel not idempotent'; END IF;

  SELECT r.offer_id INTO _offer FROM public.create_transfer_offer(
    _target, ARRAY[_seller_cards[3]], ARRAY[_target_cards[1]], 0,
    pg_catalog.now() + interval '1 minute'
  ) r;
  PERFORM public._expire_transfer_offers(pg_catalog.now() + interval '2 minutes');
  IF (SELECT status FROM public.transfer_offers WHERE id = _offer) <> 'expired' OR EXISTS (
    SELECT 1 FROM public.club_players WHERE id IN (_seller_cards[3], _target_cards[1]) AND is_reserved
  ) THEN RAISE EXCEPTION 'assertion_failed: expiration contract'; END IF;
  PERFORM pg_catalog.set_config('request.jwt.claim.sub', _users[3]::text, true);
  BEGIN
    PERFORM * FROM public.accept_transfer_offer(_offer);
    RAISE EXCEPTION 'assertion_failed: expired offer accepted';
  EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS _message = MESSAGE_TEXT;
    IF _message <> 'offer_expired' THEN RAISE; END IF;
  END;
  PERFORM pg_catalog.set_config('request.jwt.claim.sub', _users[1]::text, true);

  -- Atomic acceptance transfers every card and cash exactly once.
  UPDATE public.clubs SET balance_cents = 1000 WHERE id IN (_seller, _target);
  SELECT r.offer_id INTO _offer FROM public.create_transfer_offer(
    _target, ARRAY[_seller_cards[3], _seller_cards[4]], ARRAY[_target_cards[1]], 100,
    pg_catalog.now() + interval '1 hour'
  ) r;
  SELECT pg_catalog.count(*) INTO _ledger_before FROM public.wallet_transactions
  WHERE reference_table = 'transfer_offers' AND reference_id = _offer;
  PERFORM pg_catalog.set_config('request.jwt.claim.sub', _users[3]::text, true);
  SELECT * INTO _result FROM public.accept_transfer_offer(_offer);
  IF (SELECT pg_catalog.count(*) FROM public.club_players
      WHERE id IN (_seller_cards[3], _seller_cards[4]) AND club_id = _target) <> 2 THEN
    RAISE EXCEPTION 'assertion_failed: accept from cards';
  END IF;
  IF (SELECT club_id FROM public.club_players WHERE id = _target_cards[1]) <> _seller THEN
    RAISE EXCEPTION 'assertion_failed: accept to cards';
  END IF;
  IF EXISTS (SELECT 1 FROM public.club_players
             WHERE id IN (_seller_cards[3], _seller_cards[4], _target_cards[1]) AND is_reserved) THEN
    RAISE EXCEPTION 'assertion_failed: accept left reservation';
  END IF;
  IF (SELECT balance_cents FROM public.clubs WHERE id = _seller) <> 900
     OR (SELECT balance_cents FROM public.clubs WHERE id = _target) <> 1100 THEN
    RAISE EXCEPTION 'assertion_failed: transfer cash balances';
  END IF;
  IF (SELECT pg_catalog.count(*) FROM public.wallet_transactions
      WHERE reference_table = 'transfer_offers' AND reference_id = _offer) <> _ledger_before + 2 THEN
    RAISE EXCEPTION 'assertion_failed: transfer cash ledgers';
  END IF;
  SELECT * INTO _result FROM public.accept_transfer_offer(_offer);
  IF NOT _result.idempotent THEN RAISE EXCEPTION 'assertion_failed: accept not idempotent'; END IF;
  IF (SELECT pg_catalog.count(*) FROM public.wallet_transactions
      WHERE reference_table = 'transfer_offers' AND reference_id = _offer) <> _ledger_before + 2 THEN
    RAISE EXCEPTION 'assertion_failed: repeated accept duplicated ledger';
  END IF;

  -- Balance and ownership changes before acceptance fail with no partial effects.
  PERFORM pg_catalog.set_config('request.jwt.claim.sub', _users[1]::text, true);
  SELECT r.offer_id INTO _offer FROM public.create_transfer_offer(
    _target, ARRAY[_seller_cards[5]], ARRAY[_target_cards[2]], 500,
    pg_catalog.now() + interval '1 hour'
  ) r;
  UPDATE public.clubs SET balance_cents = 0 WHERE id = _seller;
  SELECT pg_catalog.count(*) INTO _ledger_before FROM public.wallet_transactions
  WHERE reference_table = 'transfer_offers' AND reference_id = _offer;
  PERFORM pg_catalog.set_config('request.jwt.claim.sub', _users[3]::text, true);
  BEGIN
    PERFORM * FROM public.accept_transfer_offer(_offer);
    RAISE EXCEPTION 'assertion_failed: cash failure accepted';
  EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS _message = MESSAGE_TEXT;
    IF _message <> 'insufficient_balance' THEN RAISE; END IF;
  END;
  IF (SELECT status FROM public.transfer_offers WHERE id = _offer) <> 'pending'
     OR (SELECT club_id FROM public.club_players WHERE id = _seller_cards[5]) <> _seller
     OR (SELECT club_id FROM public.club_players WHERE id = _target_cards[2]) <> _target
     OR (SELECT pg_catalog.count(*) FROM public.wallet_transactions
         WHERE reference_table = 'transfer_offers' AND reference_id = _offer) <> _ledger_before THEN
    RAISE EXCEPTION 'assertion_failed: cash failure was partial';
  END IF;

  -- The listing and offer queries expose only usable/minimal data.
  PERFORM pg_catalog.set_config(
    'request.jwt.claim.sub',
    _users[1]::text,
    true
  );

SELECT pg_catalog.count(*)
INTO _count
FROM public.list_trade_targets() t
WHERE t.club_id = ANY(_clubs);

IF _count <> 5 THEN
    RAISE EXCEPTION 'assertion_failed: fixture trade targets';
END IF;

  IF EXISTS (
    SELECT 1
    FROM public.list_trade_targets() t
    WHERE t.club_id = _clubs[1]
  ) THEN
    RAISE EXCEPTION 'assertion_failed: own club listed as trade target';
END IF;

  IF EXISTS (
    SELECT 1
    FROM public.list_market_listings() l
    WHERE l.listing_id IS NULL
  ) THEN
    RAISE EXCEPTION 'assertion_failed: listing projection';
END IF;

  IF NOT EXISTS (
    SELECT 1
    FROM public.list_my_transfer_offers() o
    WHERE o.offer_id = _offer
  ) THEN
    RAISE EXCEPTION 'assertion_failed: offer projection';
END IF;

  RAISE NOTICE 'usable_market contract test passed';
END $$;

ROLLBACK;