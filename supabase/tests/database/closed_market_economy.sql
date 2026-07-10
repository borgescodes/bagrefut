-- Transactional contract test for closed 60-card market economy.
-- Apply 20260710190000_closed_market_economy.sql and
-- 20260710191000_fix_closed_market_ambiguity.sql before running.
-- Expected final NOTICE:
--   closed_market_economy contract test passed
--
-- Safe behavior: all fixture data is rolled back.

BEGIN;

DO $$
DECLARE
_league_id uuid;
  _badge_id uuid;

  _users uuid[] := ARRAY[
    '00000000-0000-0000-0000-000000061001'::uuid,
    '00000000-0000-0000-0000-000000061002'::uuid,
    '00000000-0000-0000-0000-000000061003'::uuid,
    '00000000-0000-0000-0000-000000061004'::uuid,
    '00000000-0000-0000-0000-000000061005'::uuid
  ];

  _clubs uuid[] := ARRAY[
    '00000000-0000-0000-0000-000000061101'::uuid,
    '00000000-0000-0000-0000-000000061102'::uuid,
    '00000000-0000-0000-0000-000000061103'::uuid,
    '00000000-0000-0000-0000-000000061104'::uuid,
    '00000000-0000-0000-0000-000000061105'::uuid
  ];

  _pack_club uuid := '00000000-0000-0000-0000-000000061101'::uuid;
  _seller_club uuid := '00000000-0000-0000-0000-000000061102'::uuid;
  _full_club uuid := '00000000-0000-0000-0000-000000061103'::uuid;
  _buyer_club uuid := '00000000-0000-0000-0000-000000061104'::uuid;
  _target_club uuid := '00000000-0000-0000-0000-000000061105'::uuid;

  _initial_cards uuid[] := ARRAY[]::uuid[];
  _seller_cards uuid[] := ARRAY[]::uuid[];
  _full_cards uuid[] := ARRAY[]::uuid[];
  _buyer_cards uuid[] := ARRAY[]::uuid[];
  _target_cards uuid[] := ARRAY[]::uuid[];
  _pack_cards uuid[] := ARRAY[]::uuid[];

  _card uuid;
  _commercial_card uuid;
  _listing uuid;
  _offer uuid;
  _count integer;
  _starter_before integer;
  _starter_after integer;
  _balance integer;
  _message text;
  _result record;
  _i integer;
BEGIN
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
SET status = 'setup',
    max_clubs = 1000
WHERE id = _league_id;

FOR _i IN 1..5 LOOP
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
      _users[_i],
      '00000000-0000-0000-0000-000000000000',
      'authenticated',
      'authenticated',
      'closed-market-' || _i::text || '@example.test',
      'test-password',
      pg_catalog.now(),
      '{"provider":"email","providers":["email"]}'::jsonb,
      pg_catalog.jsonb_build_object(
        'username',
        'cmkt' || _i::text
      ),
      pg_catalog.now(),
      pg_catalog.now()
    );
END LOOP;

UPDATE public.profiles
SET status = 'approved'
WHERE id = ANY(_users);

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
VALUES
    (
        _clubs[1],
        _league_id,
        _users[1],
        'CM Pack',
        public.normalize_club_name('CM Pack'),
        'CMP',
        _badge_id,
        50000
    ),
    (
        _clubs[2],
        _league_id,
        _users[2],
        'CM Seller',
        public.normalize_club_name('CM Seller'),
        'CMS',
        _badge_id,
        9950
    ),
    (
        _clubs[3],
        _league_id,
        _users[3],
        'CM Full',
        public.normalize_club_name('CM Full'),
        'CMF',
        _badge_id,
        1000
    ),
    (
        _clubs[4],
        _league_id,
        _users[4],
        'CM Buyer',
        public.normalize_club_name('CM Buyer'),
        'CMB',
        _badge_id,
        50000
    ),
    (
        _clubs[5],
        _league_id,
        _users[5],
        'CM Target',
        public.normalize_club_name('CM Target'),
        'CMT',
        _badge_id,
        9950
    );

INSERT INTO public.initial_packs(club_id)
VALUES (_pack_club);

-- Every inserted player receives one permanent club_players row and one
-- starter-pool stock row through trg_players_create_system_card.
FOR _i IN 1..45 LOOP
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
    VALUES (
      'BFCM-' || pg_catalog.lpad(_i::text, 3, '0'),
      'Closed Market Player ' || _i::text,
      (ARRAY['GK', 'DEF', 'MID', 'ATA'])[
        ((_i - 1) % 4) + 1
      ]::public.player_position,
      'peba',
      'centro',
      1,
      CASE WHEN _i % 4 = 1 THEN 44 ELSE 52 END,
      CASE WHEN _i % 4 = 0 THEN 57 ELSE 41 END,
      CASE WHEN _i % 4 = 3 THEN 58 ELSE 43 END,
      CASE WHEN _i % 4 = 3 THEN 56 ELSE 42 END,
      CASE WHEN _i % 4 = 2 THEN 58 ELSE 44 END,
      CASE WHEN _i % 4 = 2 THEN 55 ELSE 45 END,
      CASE WHEN _i % 4 = 1 THEN 60 ELSE 6 END,
      1
    );

SELECT cp.id
INTO _card
FROM public.club_players cp
         JOIN public.players p ON p.id = cp.player_id
WHERE p.code = 'BFCM-' || pg_catalog.lpad(_i::text, 3, '0');

IF _i <= 10 THEN
      _initial_cards := _initial_cards || _card;
    ELSIF _i <= 16 THEN
DELETE FROM public.system_market_stock
WHERE club_player_id = _card;

UPDATE public.club_players
SET club_id = _seller_club
WHERE id = _card;

_seller_cards := _seller_cards || _card;
    ELSIF _i <= 26 THEN
DELETE FROM public.system_market_stock
WHERE club_player_id = _card;

UPDATE public.club_players
SET club_id = _full_club
WHERE id = _card;

_full_cards := _full_cards || _card;
    ELSIF _i <= 35 THEN
DELETE FROM public.system_market_stock
WHERE club_player_id = _card;

UPDATE public.club_players
SET club_id = _buyer_club
WHERE id = _card;

_buyer_cards := _buyer_cards || _card;
ELSE
DELETE FROM public.system_market_stock
WHERE club_player_id = _card;

UPDATE public.club_players
SET club_id = _target_club
WHERE id = _card;

_target_cards := _target_cards || _card;
END IF;
END LOOP;

  -- Fixture sanity.
  IF pg_catalog.array_length(_initial_cards, 1) <> 10
    OR pg_catalog.array_length(_seller_cards, 1) <> 6
    OR pg_catalog.array_length(_full_cards, 1) <> 10
    OR pg_catalog.array_length(_buyer_cards, 1) <> 9
    OR pg_catalog.array_length(_target_cards, 1) <> 10 THEN
    RAISE EXCEPTION 'assertion_failed: fixture roster sizes';
END IF;

  -- Initial starter pool must be invisible to approved non-admin users.
  PERFORM pg_catalog.set_config(
    'request.jwt.claim.sub',
    _users[2]::text,
    true
  );

EXECUTE 'SET LOCAL ROLE authenticated';

SELECT pg_catalog.count(*)::integer
INTO _count
FROM public.system_market_stock sms
WHERE sms.club_player_id = ANY(_initial_cards);

IF _count <> 0 THEN
    EXECUTE 'RESET ROLE';
    RAISE EXCEPTION
      'assertion_failed: starter stock visible in system market';
END IF;

SELECT pg_catalog.count(*)::integer
INTO _count
FROM public.club_players cp
WHERE cp.id = ANY(_initial_cards)
  AND cp.club_id IS NULL;

EXECUTE 'RESET ROLE';

IF _count <> 0 THEN
    RAISE EXCEPTION
      'assertion_failed: starter club_players visible';
END IF;

  -- Club with six cards sells one. Balance may pass R$ 100,00.
  PERFORM pg_catalog.set_config(
    'request.jwt.claim.sub',
    _users[2]::text,
    true
  );

SELECT *
INTO _result
FROM public.sell_player_to_system(_seller_cards[1]);

_commercial_card := _seller_cards[1];

  IF _result.roster_size <> 5 THEN
    RAISE EXCEPTION
      'assertion_failed: system sale did not leave roster at five';
END IF;

  IF _result.balance_cents <= 10000
    OR _result.balance_cents > 99999 THEN
    RAISE EXCEPTION
      'assertion_failed: balance above R$100 and below cap';
END IF;

  IF NOT EXISTS (
    SELECT 1
    FROM public.system_market_stock sms
    WHERE sms.club_player_id = _commercial_card
      AND sms.acquired_from_club_id = _seller_club
      AND sms.is_market_eligible
  ) THEN
    RAISE EXCEPTION
      'assertion_failed: sold card not commercial stock';
END IF;

  -- Commercial stock is visible; starter stock remains hidden.
  PERFORM pg_catalog.set_config(
    'request.jwt.claim.sub',
    _users[4]::text,
    true
  );

EXECUTE 'SET LOCAL ROLE authenticated';

SELECT pg_catalog.count(*)::integer
INTO _count
FROM public.system_market_stock sms
WHERE sms.club_player_id = _commercial_card;

EXECUTE 'RESET ROLE';

IF _count <> 1 THEN
    RAISE EXCEPTION
      'assertion_failed: commercial system stock visibility';
END IF;

  -- A full roster cannot buy commercial system stock.
  PERFORM pg_catalog.set_config(
    'request.jwt.claim.sub',
    _users[3]::text,
    true
  );

BEGIN
    PERFORM *
    FROM public.buy_player_from_system(_commercial_card);

    RAISE EXCEPTION
      'assertion_failed: ten-card club bought system card';
EXCEPTION
    WHEN OTHERS THEN
      GET STACKED DIAGNOSTICS _message = MESSAGE_TEXT;
      IF _message <> 'roster_maximum_reached' THEN
        RAISE;
END IF;
END;

  -- A starter-pool card cannot be bought, even by a nine-card club.
  PERFORM pg_catalog.set_config(
    'request.jwt.claim.sub',
    _users[4]::text,
    true
  );

BEGIN
    PERFORM *
    FROM public.buy_player_from_system(_initial_cards[1]);

    RAISE EXCEPTION
      'assertion_failed: starter card bought from system';
EXCEPTION
    WHEN OTHERS THEN
      GET STACKED DIAGNOSTICS _message = MESSAGE_TEXT;
      IF _message <> 'player_not_in_system_stock' THEN
        RAISE;
END IF;
END;

  -- Opening a pack consumes exactly 10 cards from the global starter pool
  -- and leaves commercial stock untouched. The selected starter cards are
  -- intentionally random, so the test validates pool deltas instead of
  -- requiring the ten fixture starter cards specifically.
SELECT pg_catalog.count(*)::integer
INTO _starter_before
FROM public.system_market_stock sms
WHERE NOT sms.is_market_eligible;

PERFORM pg_catalog.set_config(
    'request.jwt.claim.sub',
    _users[1]::text,
    true
  );

SELECT pg_catalog.count(*)::integer
INTO _count
FROM public.open_initial_pack(_pack_club);

IF _count <> 10 THEN
    RAISE EXCEPTION
      'assertion_failed: initial pack did not return ten cards';
END IF;

SELECT pg_catalog.count(*)::integer
INTO _count
FROM public.club_players cp
WHERE cp.club_id = _pack_club;

IF _count <> 10 THEN
    RAISE EXCEPTION
      'assertion_failed: pack club roster not ten';
END IF;

  IF NOT EXISTS (
    SELECT 1
    FROM public.system_market_stock sms
    WHERE sms.club_player_id = _commercial_card
      AND sms.acquired_from_club_id = _seller_club
      AND sms.is_market_eligible
  ) THEN
    RAISE EXCEPTION
      'assertion_failed: pack consumed commercial stock';
END IF;

SELECT pg_catalog.count(*)::integer
INTO _starter_after
FROM public.system_market_stock sms
WHERE NOT sms.is_market_eligible;

IF _starter_after <> _starter_before - 10 THEN
    RAISE EXCEPTION
      'assertion_failed: starter pool did not decrease by ten';
END IF;

SELECT pg_catalog.array_agg(cp.id ORDER BY p.code)
INTO _pack_cards
FROM public.club_players cp
         JOIN public.players p ON p.id = cp.player_id
WHERE cp.club_id = _pack_club;

-- Target lists one card. A full club cannot buy it.
PERFORM pg_catalog.set_config(
    'request.jwt.claim.sub',
    _users[5]::text,
    true
  );

SELECT r.listing_id
INTO _listing
FROM public.create_market_listing(
             _target_cards[1],
             100
     ) AS r;

PERFORM pg_catalog.set_config(
    'request.jwt.claim.sub',
    _users[1]::text,
    true
  );

BEGIN
    PERFORM *
    FROM public.buy_market_listing(_listing);

    RAISE EXCEPTION
      'assertion_failed: ten-card club bought P2P listing';
EXCEPTION
    WHEN OTHERS THEN
      GET STACKED DIAGNOSTICS _message = MESSAGE_TEXT;
      IF _message <> 'roster_maximum' THEN
        RAISE;
END IF;
END;

  -- Nine-card buyer purchases listing and reaches ten.
  PERFORM pg_catalog.set_config(
    'request.jwt.claim.sub',
    _users[4]::text,
    true
  );

SELECT *
INTO _result
FROM public.buy_market_listing(_listing);

IF _result.buyer_roster_size <> 10
    OR _result.seller_roster_size <> 9 THEN
    RAISE EXCEPTION
      'assertion_failed: P2P roster projection';
END IF;

SELECT c.balance_cents
INTO _balance
FROM public.clubs c
WHERE c.id = _target_club;

IF _balance <> 10050 THEN
    RAISE EXCEPTION
      'assertion_failed: P2P seller balance above R$100';
END IF;

  -- Target is now at nine and may buy the commercial system card.
  PERFORM pg_catalog.set_config(
    'request.jwt.claim.sub',
    _users[5]::text,
    true
  );

SELECT *
INTO _result
FROM public.buy_player_from_system(_commercial_card);

IF _result.roster_size <> 10 THEN
    RAISE EXCEPTION
      'assertion_failed: system buy did not restore roster to ten';
END IF;

  IF EXISTS (
    SELECT 1
    FROM public.system_market_stock sms
    WHERE sms.club_player_id = _commercial_card
  ) THEN
    RAISE EXCEPTION
      'assertion_failed: commercial stock not removed after purchase';
END IF;

  -- Direct offer projection cannot create an 11-card roster.
  PERFORM pg_catalog.set_config(
    'request.jwt.claim.sub',
    _users[1]::text,
    true
  );

BEGIN
    PERFORM *
    FROM public.create_transfer_offer(
      _target_club,
      ARRAY[]::uuid[],
      ARRAY[_target_cards[2]],
      0,
      pg_catalog.now() + interval '24 hours'
    );

    RAISE EXCEPTION
      'assertion_failed: offer projected roster above ten';
EXCEPTION
    WHEN OTHERS THEN
      GET STACKED DIAGNOSTICS _message = MESSAGE_TEXT;
      IF _message <> 'roster_maximum' THEN
        RAISE;
END IF;
END;

  -- Receiving cash that would produce R$ 1.000,00 is blocked.
UPDATE public.clubs
SET balance_cents = 95000
WHERE id = _target_club;

BEGIN
    PERFORM *
    FROM public.create_transfer_offer(
      _target_club,
      ARRAY[_pack_cards[1]],
      ARRAY[_target_cards[2]],
      5000,
      pg_catalog.now() + interval '24 hours'
    );

    RAISE EXCEPTION
      'assertion_failed: offer exceeded wallet cap';
EXCEPTION
    WHEN OTHERS THEN
      GET STACKED DIAGNOSTICS _message = MESSAGE_TEXT;
      IF _message <> 'wallet_balance_cap_exceeded' THEN
        RAISE;
END IF;
END;

UPDATE public.clubs
SET balance_cents = 10000
WHERE id = _target_club;

-- Valid 1x1 + R$100 cash keeps both rosters at ten and permits balance
-- above R$100.
SELECT r.offer_id
INTO _offer
FROM public.create_transfer_offer(
             _target_club,
             ARRAY[_pack_cards[1]],
             ARRAY[_target_cards[2]],
             10000,
             pg_catalog.now() + interval '24 hours'
     ) AS r;

PERFORM pg_catalog.set_config(
    'request.jwt.claim.sub',
    _users[5]::text,
    true
  );

SELECT *
INTO _result
FROM public.accept_transfer_offer(_offer);

IF _result.status <> 'accepted' THEN
    RAISE EXCEPTION
      'assertion_failed: valid transfer not accepted';
END IF;

  IF (
SELECT pg_catalog.count(*)
FROM public.club_players cp
WHERE cp.club_id = _pack_club
    ) <> 10 OR (
    SELECT pg_catalog.count(*)
    FROM public.club_players cp
    WHERE cp.club_id = _target_club
  ) <> 10 THEN
    RAISE EXCEPTION
      'assertion_failed: accepted transfer roster sizes';
END IF;

  IF NOT EXISTS (
    SELECT 1
    FROM public.club_players cp
    WHERE cp.id = _pack_cards[1]
      AND cp.club_id = _target_club
  ) OR NOT EXISTS (
    SELECT 1
    FROM public.club_players cp
    WHERE cp.id = _target_cards[2]
      AND cp.club_id = _pack_club
  ) THEN
    RAISE EXCEPTION
      'assertion_failed: accepted transfer ownership';
END IF;

  IF (
SELECT c.balance_cents
FROM public.clubs c
WHERE c.id = _pack_club
    ) <> 40000 OR (
    SELECT c.balance_cents
    FROM public.clubs c
    WHERE c.id = _target_club
  ) <> 20000 THEN
    RAISE EXCEPTION
      'assertion_failed: accepted transfer balances';
END IF;

  -- Exact wallet ceiling: 99.999 succeeds; 100.000 fails.
UPDATE public.clubs
SET balance_cents = 99998
WHERE id = _full_club;

SELECT public._credit_wallet(
               _full_club,
               1,
               'market_sale',
               'closed_market_test',
               _full_club,
               'wallet cap contract test'
       )
INTO _balance;

IF _balance <> 99999 THEN
    RAISE EXCEPTION
      'assertion_failed: exact wallet cap not accepted';
END IF;

BEGIN
    PERFORM public._credit_wallet(
      _full_club,
      1,
      'market_sale',
      'closed_market_test',
      _full_club,
      'wallet cap overflow test'
    );

    RAISE EXCEPTION
      'assertion_failed: wallet credit exceeded 99999';
EXCEPTION
    WHEN OTHERS THEN
      GET STACKED DIAGNOSTICS _message = MESSAGE_TEXT;
      IF _message <> 'wallet_balance_cap_exceeded' THEN
        RAISE;
END IF;
END;

BEGIN
UPDATE public.clubs
SET balance_cents = 100000
WHERE id = _full_club;

RAISE EXCEPTION
      'assertion_failed: clubs balance constraint exceeded';
EXCEPTION
    WHEN check_violation THEN
      NULL;
END;

BEGIN
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
           _full_club,
           1,
           100000,
           'market_sale',
           'closed_market_test',
           _full_club,
           'ledger cap overflow test'
       );

RAISE EXCEPTION
      'assertion_failed: wallet ledger constraint exceeded';
EXCEPTION
    WHEN check_violation THEN
      NULL;
END;

SET CONSTRAINTS ALL IMMEDIATE;

RAISE NOTICE
    'closed_market_economy contract test passed';
END;
$$;

ROLLBACK;