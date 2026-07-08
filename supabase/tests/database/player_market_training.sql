-- Local database contract test for derived players, system market, and training.
-- Intended for a local Supabase/Postgres database. The script is transactional
-- and rolls back all fixture data at the end.

BEGIN;

DO $$
DECLARE
  _league_id uuid;
  _badge_id uuid;
  _seller_user uuid := '00000000-0000-0000-0000-000000041001'::uuid;
  _buyer_user uuid := '00000000-0000-0000-0000-000000041002'::uuid;
  _poor_user uuid := '00000000-0000-0000-0000-000000041003'::uuid;
  _cap_user uuid := '00000000-0000-0000-0000-000000041004'::uuid;
  _train_user uuid := '00000000-0000-0000-0000-000000041005'::uuid;
  _pending_user uuid := '00000000-0000-0000-0000-000000041006'::uuid;
  _blocked_user uuid := '00000000-0000-0000-0000-000000041007'::uuid;
  _pack_user uuid := '00000000-0000-0000-0000-000000041008'::uuid;
  _seller_club uuid := '00000000-0000-0000-0000-000000041101'::uuid;
  _buyer_club uuid := '00000000-0000-0000-0000-000000041102'::uuid;
  _poor_club uuid := '00000000-0000-0000-0000-000000041103'::uuid;
  _cap_club uuid := '00000000-0000-0000-0000-000000041104'::uuid;
  _train_club uuid := '00000000-0000-0000-0000-000000041105'::uuid;
  _pending_club uuid := '00000000-0000-0000-0000-000000041106'::uuid;
  _blocked_club uuid := '00000000-0000-0000-0000-000000041107'::uuid;
  _pack_club uuid := '00000000-0000-0000-0000-000000041108'::uuid;
  _all_users uuid[];
  _all_clubs uuid[];
  _seller_cards uuid[] := ARRAY[]::uuid[];
  _buyer_cards uuid[] := ARRAY[]::uuid[];
  _cap_cards uuid[] := ARRAY[]::uuid[];
  _train_cards uuid[] := ARRAY[]::uuid[];
  _card_id uuid;
  _player_id uuid;
  _system_card uuid;
  _other_system_card uuid;
  _count integer;
  _price integer;
  _balance integer;
  _roster integer;
  _before_balance integer;
  _after_balance integer;
  _before_attr integer;
  _after_attr integer;
  _before_ovr integer;
  _after_ovr integer;
  _before_ref integer;
  _after_ref integer;
  _message text;
  _blocked boolean;
  _i integer;
  _result record;
BEGIN
  _all_users := ARRAY[
    _seller_user,
    _buyer_user,
    _poor_user,
    _cap_user,
    _train_user,
    _pending_user,
    _blocked_user,
    _pack_user
  ];
  _all_clubs := ARRAY[
    _seller_club,
    _buyer_club,
    _poor_club,
    _cap_club,
    _train_club,
    _pending_club,
    _blocked_club,
    _pack_club
  ];

  SELECT l.id INTO _league_id
  FROM public.leagues l
  WHERE l.slug = 'bagreleirao';

  IF _league_id IS NULL THEN
    RAISE EXCEPTION 'test_setup_failed: bagreleirao league not found';
  END IF;

  UPDATE public.leagues
  SET status = 'setup',
      max_clubs = 1000
  WHERE id = _league_id;

  SELECT b.id INTO _badge_id
  FROM public.club_badges b
  WHERE b.is_active
  ORDER BY b.sort_order, b.code
  LIMIT 1;

  IF _badge_id IS NULL THEN
    RAISE EXCEPTION 'test_setup_failed: active badge not found';
  END IF;

  DELETE FROM public.initial_pack_items ipi
  USING public.initial_packs ip
  WHERE ipi.pack_id = ip.id
    AND ip.club_id = ANY(_all_clubs);

  DELETE FROM public.training_sessions ts
  WHERE ts.club_id = ANY(_all_clubs);

  DELETE FROM public.club_player_attribute_progress cpp
  USING public.club_players cp
  WHERE cpp.club_player_id = cp.id
    AND (
      cp.club_id = ANY(_all_clubs)
      OR cp.player_id IN (SELECT p.id FROM public.players p WHERE p.code LIKE 'BFPMT-%')
    );

  DELETE FROM public.club_players cp
  WHERE cp.club_id = ANY(_all_clubs)
     OR cp.player_id IN (SELECT p.id FROM public.players p WHERE p.code LIKE 'BFPMT-%');

  DELETE FROM public.initial_packs ip
  WHERE ip.club_id = ANY(_all_clubs);

  DELETE FROM public.wallet_transactions wt
  WHERE wt.club_id = ANY(_all_clubs);

  DELETE FROM public.clubs c
  WHERE c.id = ANY(_all_clubs)
     OR c.owner_id = ANY(_all_users);

  DELETE FROM public.players p
  WHERE p.code LIKE 'BFPMT-%';

  DELETE FROM public.profiles p
  WHERE p.id = ANY(_all_users);

  DELETE FROM auth.users u
  WHERE u.id = ANY(_all_users);

  FOR _i IN 1..pg_catalog.array_length(_all_users, 1) LOOP
    INSERT INTO auth.users (
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
      _all_users[_i],
      '00000000-0000-0000-0000-000000000000',
      'authenticated',
      'authenticated',
      'player-market-training-' || _i::text || '@example.test',
      'test-password',
      pg_catalog.now(),
      '{"provider":"email","providers":["email"]}'::jsonb,
      pg_catalog.jsonb_build_object('username', 'pmt' || pg_catalog.lpad(_i::text, 2, '0')),
      pg_catalog.now(),
      pg_catalog.now()
    );
  END LOOP;

  UPDATE public.profiles
  SET status = 'approved'::public.user_status
  WHERE id IN (_seller_user, _buyer_user, _poor_user, _cap_user, _train_user, _pack_user);

  UPDATE public.profiles
  SET status = 'pending'::public.user_status
  WHERE id = _pending_user;

  UPDATE public.profiles
  SET status = 'blocked'::public.user_status
  WHERE id = _blocked_user;

  INSERT INTO public.clubs (id, league_id, owner_id, name, normalized_name, abbreviation, badge_id, balance_cents)
  VALUES
    (_seller_club, _league_id, _seller_user, 'PMT Seller', public.normalize_club_name('PMT Seller'), 'PMS', _badge_id, 0),
    (_buyer_club, _league_id, _buyer_user, 'PMT Buyer', public.normalize_club_name('PMT Buyer'), 'PMB', _badge_id, 10000),
    (_poor_club, _league_id, _poor_user, 'PMT Poor', public.normalize_club_name('PMT Poor'), 'PMP', _badge_id, 0),
    (_cap_club, _league_id, _cap_user, 'PMT Cap', public.normalize_club_name('PMT Cap'), 'PMC', _badge_id, 9990),
    (_train_club, _league_id, _train_user, 'PMT Train', public.normalize_club_name('PMT Train'), 'PMT', _badge_id, 1000),
    (_pending_club, _league_id, _pending_user, 'PMT Pending', public.normalize_club_name('PMT Pending'), 'PMPD', _badge_id, 1000),
    (_blocked_club, _league_id, _blocked_user, 'PMT Blocked', public.normalize_club_name('PMT Blocked'), 'PMBL', _badge_id, 1000),
    (_pack_club, _league_id, _pack_user, 'PMT Pack', public.normalize_club_name('PMT Pack'), 'PMPK', _badge_id, 1000);

  INSERT INTO public.initial_packs (club_id)
  VALUES (_pack_club);

  -- Seed contract: distribution stays canonical and attributes are not flat.
  SELECT pg_catalog.count(*) INTO _count
  FROM public.players p
  WHERE p.code ~ '^(GK|DEF|MID|ATA)[0-9]{2}$';
  IF _count <> 60 THEN
    RAISE EXCEPTION 'assertion_failed: expected 60 canonical seed players, got %', _count;
  END IF;

  SELECT pg_catalog.count(*) INTO _count
  FROM public.players p
  WHERE p.code ~ '^(GK|DEF|MID|ATA)[0-9]{2}$'
    AND p.velocity = p.finishing
    AND p.finishing = p.passing
    AND p.passing = p.dribbling
    AND p.dribbling = p.defending
    AND p.defending = p.physical
    AND p.physical = p.goalkeeping;
  IF _count <> 0 THEN
    RAISE EXCEPTION 'assertion_failed: seed still has flat attributes';
  END IF;

  SELECT pg_catalog.count(*) INTO _count
  FROM public.players p
  WHERE p.code ~ '^(GK|DEF|MID|ATA)[0-9]{2}$'
    AND (
      p.overall <> public.calculate_player_overall(p.position, p.velocity, p.finishing, p.passing, p.dribbling, p.defending, p.physical, p.goalkeeping)
      OR p.reference_value_cents <> public.calculate_reference_value_cents(p.rarity, p.overall, p.position)
      OR (p.rarity = 'peba'::public.player_rarity AND p.overall NOT BETWEEN 40 AND 59)
      OR (p.rarity = 'paia'::public.player_rarity AND p.overall NOT BETWEEN 60 AND 74)
      OR (p.rarity = 'pika'::public.player_rarity AND p.overall NOT BETWEEN 75 AND 89)
    );
  IF _count <> 0 THEN
    RAISE EXCEPTION 'assertion_failed: seed derived values invalid';
  END IF;

  SELECT pg_catalog.count(*) INTO _count
  FROM public.players p
  WHERE p.code ~ '^(GK|DEF|MID|ATA)[0-9]{2}$'
    AND (
      (p.position = 'GK'::public.player_position AND NOT (p.goalkeeping > p.defending AND p.goalkeeping > p.physical))
      OR (p.position = 'DEF'::public.player_position AND NOT (p.defending >= p.velocity AND p.physical >= p.dribbling))
      OR (p.position = 'MID'::public.player_position AND NOT (p.passing > p.velocity AND p.dribbling > p.defending))
      OR (p.position = 'ATA'::public.player_position AND NOT (p.finishing > p.passing AND p.velocity > p.defending))
      OR (p.position <> 'GK'::public.player_position AND p.goalkeeping > 20)
    );
  IF _count <> 0 THEN
    RAISE EXCEPTION 'assertion_failed: seed positional strengths invalid';
  END IF;

  IF (SELECT pg_catalog.count(*) FROM public.players p WHERE p.rarity = 'peba'::public.player_rarity AND p.code ~ '^(GK|DEF|MID|ATA)[0-9]{2}$') <> 35 THEN
    RAISE EXCEPTION 'assertion_failed: peba distribution changed';
  END IF;
  IF (SELECT pg_catalog.count(*) FROM public.players p WHERE p.rarity = 'paia'::public.player_rarity AND p.code ~ '^(GK|DEF|MID|ATA)[0-9]{2}$') <> 20 THEN
    RAISE EXCEPTION 'assertion_failed: paia distribution changed';
  END IF;
  IF (SELECT pg_catalog.count(*) FROM public.players p WHERE p.rarity = 'pika'::public.player_rarity AND p.code ~ '^(GK|DEF|MID|ATA)[0-9]{2}$') <> 5 THEN
    RAISE EXCEPTION 'assertion_failed: pika distribution changed';
  END IF;

  -- Fixture players. Trigger creates one system card for each player.
  FOR _i IN 1..70 LOOP
    INSERT INTO public.players (
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
      'BFPMT-' || pg_catalog.lpad(_i::text, 3, '0'),
      'PMT Player ' || _i::text,
      (ARRAY['GK','DEF','MID','ATA'])[((_i - 1) % 4) + 1]::public.player_position,
      CASE WHEN _i <= 50 THEN 'peba'::public.player_rarity WHEN _i <= 65 THEN 'paia'::public.player_rarity ELSE 'pika'::public.player_rarity END,
      'centro'::public.player_sector,
      1,
      CASE WHEN (_i % 4) = 1 THEN 44 ELSE 52 END,
      CASE WHEN (_i % 4) = 0 THEN 57 ELSE 41 END,
      CASE WHEN (_i % 4) = 3 THEN 58 ELSE 43 END,
      CASE WHEN (_i % 4) = 3 THEN 56 ELSE 42 END,
      CASE WHEN (_i % 4) = 2 THEN 58 ELSE 44 END,
      CASE WHEN (_i % 4) = 2 THEN 55 ELSE 45 END,
      CASE WHEN (_i % 4) = 1 THEN 60 ELSE 6 END,
      1
    );
  END LOOP;

  IF EXISTS (
    SELECT 1
    FROM public.players p
    LEFT JOIN public.club_players cp ON cp.player_id = p.id
    WHERE p.code LIKE 'BFPMT-%'
    GROUP BY p.id
    HAVING pg_catalog.count(cp.id) <> 1
  ) THEN
    RAISE EXCEPTION 'assertion_failed: fixture player without exactly one card';
  END IF;

  -- Move fixture cards to clubs by transferring the permanent card.
  FOR _i IN 1..6 LOOP
    SELECT cp.id INTO _card_id
    FROM public.club_players cp
    JOIN public.players p ON p.id = cp.player_id
    WHERE p.code = 'BFPMT-' || pg_catalog.lpad(_i::text, 3, '0')
    FOR UPDATE;
    DELETE FROM public.system_market_stock WHERE club_player_id = _card_id;
    UPDATE public.club_players SET club_id = _seller_club WHERE id = _card_id;
    _seller_cards := _seller_cards || _card_id;
  END LOOP;

  FOR _i IN 7..20 LOOP
    SELECT cp.id INTO _card_id
    FROM public.club_players cp
    JOIN public.players p ON p.id = cp.player_id
    WHERE p.code = 'BFPMT-' || pg_catalog.lpad(_i::text, 3, '0')
    FOR UPDATE;
    DELETE FROM public.system_market_stock WHERE club_player_id = _card_id;
    UPDATE public.club_players SET club_id = _buyer_club WHERE id = _card_id;
    _buyer_cards := _buyer_cards || _card_id;
  END LOOP;

  FOR _i IN 21..26 LOOP
    SELECT cp.id INTO _card_id
    FROM public.club_players cp
    JOIN public.players p ON p.id = cp.player_id
    WHERE p.code = 'BFPMT-' || pg_catalog.lpad(_i::text, 3, '0')
    FOR UPDATE;
    DELETE FROM public.system_market_stock WHERE club_player_id = _card_id;
    UPDATE public.club_players SET club_id = _cap_club WHERE id = _card_id;
    _cap_cards := _cap_cards || _card_id;
  END LOOP;

  FOR _i IN 27..32 LOOP
    SELECT cp.id INTO _card_id
    FROM public.club_players cp
    JOIN public.players p ON p.id = cp.player_id
    WHERE p.code = 'BFPMT-' || pg_catalog.lpad(_i::text, 3, '0')
    FOR UPDATE;
    DELETE FROM public.system_market_stock WHERE club_player_id = _card_id;
    UPDATE public.club_players SET club_id = _train_club WHERE id = _card_id;
    _train_cards := _train_cards || _card_id;
  END LOOP;

  SELECT cp.id INTO _system_card
  FROM public.club_players cp
  JOIN public.players p ON p.id = cp.player_id
  WHERE p.code = 'BFPMT-033';

  SELECT cp.id INTO _other_system_card
  FROM public.club_players cp
  JOIN public.players p ON p.id = cp.player_id
  WHERE p.code = 'BFPMT-034';

  IF EXISTS (
    SELECT 1
    FROM public.club_players cp
    WHERE (cp.club_id IS NULL) <> EXISTS (
      SELECT 1
      FROM public.system_market_stock sms
      WHERE sms.club_player_id = cp.id
    )
  ) THEN
    RAISE EXCEPTION 'assertion_failed: stock invariant violated';
  END IF;

  IF EXISTS (
    SELECT cp.player_id
    FROM public.club_players cp
    GROUP BY cp.player_id
    HAVING pg_catalog.count(*) > 1
  ) THEN
    RAISE EXCEPTION 'assertion_failed: player in more than one card';
  END IF;

  PERFORM pg_catalog.set_config('request.jwt.claim.sub', _pending_user::text, true);
  BEGIN
    PERFORM * FROM public.buy_player_from_system(_system_card);
    RAISE EXCEPTION 'assertion_failed: pending user bought from system';
  EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS _message = MESSAGE_TEXT;
    IF _message <> 'profile_not_approved' THEN
      RAISE EXCEPTION 'assertion_failed: expected profile_not_approved, got %', _message;
    END IF;
  END;

  PERFORM pg_catalog.set_config('request.jwt.claim.sub', _blocked_user::text, true);
  BEGIN
    PERFORM * FROM public.sell_player_to_system(_seller_cards[1]);
    RAISE EXCEPTION 'assertion_failed: blocked user sold to system';
  EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS _message = MESSAGE_TEXT;
    IF _message <> 'profile_not_approved' THEN
      RAISE EXCEPTION 'assertion_failed: expected profile_not_approved, got %', _message;
    END IF;
  END;

  _blocked := false;
  PERFORM pg_catalog.set_config('request.jwt.claim.sub', _seller_user::text, true);
  BEGIN
    EXECUTE 'SET LOCAL ROLE authenticated';
    UPDATE public.system_market_stock SET acquired_price_cents = 1 WHERE club_player_id = _system_card;
    EXECUTE 'RESET ROLE';
  EXCEPTION WHEN OTHERS THEN
    _blocked := true;
    EXECUTE 'RESET ROLE';
  END;
  IF NOT _blocked THEN
    RAISE EXCEPTION 'assertion_failed: direct DML on system_market_stock succeeded';
  END IF;

  UPDATE public.club_players SET is_reserved = true WHERE id = _seller_cards[1];
  PERFORM pg_catalog.set_config('request.jwt.claim.sub', _seller_user::text, true);
  BEGIN
    PERFORM * FROM public.sell_player_to_system(_seller_cards[1]);
    RAISE EXCEPTION 'assertion_failed: reserved card sold';
  EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS _message = MESSAGE_TEXT;
    IF _message <> 'card_reserved' THEN
      RAISE EXCEPTION 'assertion_failed: expected card_reserved, got %', _message;
    END IF;
  END;
  UPDATE public.club_players SET is_reserved = false WHERE id = _seller_cards[1];

  SELECT p.reference_value_cents, c.balance_cents
  INTO _price, _before_balance
  FROM public.club_players cp
  JOIN public.players p ON p.id = cp.player_id
  JOIN public.clubs c ON c.id = cp.club_id
  WHERE cp.id = _seller_cards[1];
  _price := pg_catalog.floor(_price / 2.0)::integer;

  SELECT result.price_cents, result.balance_cents, result.roster_size
  INTO _result
  FROM public.sell_player_to_system(_seller_cards[1]) AS result;

  IF _result.price_cents <> _price OR _result.balance_cents <> _before_balance + _price OR _result.roster_size <> 5 THEN
    RAISE EXCEPTION 'assertion_failed: wrong sale result';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM public.system_market_stock WHERE club_player_id = _seller_cards[1]) THEN
    RAISE EXCEPTION 'assertion_failed: sale did not insert stock';
  END IF;
  IF NOT EXISTS (
    SELECT 1
    FROM public.wallet_transactions wt
    WHERE wt.club_id = _seller_club
      AND wt.kind = 'system_sale'::public.wallet_transaction_type
      AND wt.amount_cents = _price
      AND wt.reference_id = _seller_cards[1]
  ) THEN
    RAISE EXCEPTION 'assertion_failed: sale ledger missing';
  END IF;

  BEGIN
    PERFORM * FROM public.sell_player_to_system(_seller_cards[2]);
    RAISE EXCEPTION 'assertion_failed: sale with five-card roster succeeded';
  EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS _message = MESSAGE_TEXT;
    IF _message <> 'roster_minimum_reached' THEN
      RAISE EXCEPTION 'assertion_failed: expected roster_minimum_reached, got %', _message;
    END IF;
  END;

  PERFORM pg_catalog.set_config('request.jwt.claim.sub', _buyer_user::text, true);
  SELECT p.reference_value_cents, c.balance_cents
  INTO _price, _before_balance
  FROM public.club_players cp
  JOIN public.players p ON p.id = cp.player_id
  CROSS JOIN public.clubs c
  WHERE cp.id = _seller_cards[1]
    AND c.id = _buyer_club;

  SELECT result.price_cents, result.balance_cents, result.roster_size
  INTO _result
  FROM public.buy_player_from_system(_seller_cards[1]) AS result;

  IF _result.price_cents <> _price OR _result.balance_cents <> _before_balance - _price OR _result.roster_size <> 15 THEN
    RAISE EXCEPTION 'assertion_failed: wrong purchase result';
  END IF;
  IF EXISTS (SELECT 1 FROM public.system_market_stock WHERE club_player_id = _seller_cards[1]) THEN
    RAISE EXCEPTION 'assertion_failed: purchase left stock row';
  END IF;
  IF NOT EXISTS (
    SELECT 1
    FROM public.wallet_transactions wt
    WHERE wt.club_id = _buyer_club
      AND wt.kind = 'system_purchase'::public.wallet_transaction_type
      AND wt.amount_cents = -_price
      AND wt.reference_id = _seller_cards[1]
  ) THEN
    RAISE EXCEPTION 'assertion_failed: purchase ledger missing';
  END IF;

  BEGIN
    PERFORM * FROM public.buy_player_from_system(_system_card);
    RAISE EXCEPTION 'assertion_failed: purchase with full roster succeeded';
  EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS _message = MESSAGE_TEXT;
    IF _message <> 'roster_maximum_reached' THEN
      RAISE EXCEPTION 'assertion_failed: expected roster_maximum_reached, got %', _message;
    END IF;
  END;

  PERFORM pg_catalog.set_config('request.jwt.claim.sub', _poor_user::text, true);
  SELECT pg_catalog.count(*) INTO _count
  FROM public.system_market_stock
  WHERE club_player_id = _system_card;
  BEGIN
    PERFORM * FROM public.buy_player_from_system(_system_card);
    RAISE EXCEPTION 'assertion_failed: poor club purchase succeeded';
  EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS _message = MESSAGE_TEXT;
    IF _message <> 'insufficient_balance_or_club_missing' THEN
      RAISE EXCEPTION 'assertion_failed: expected insufficient_balance_or_club_missing, got %', _message;
    END IF;
  END;
  IF (SELECT pg_catalog.count(*) FROM public.system_market_stock WHERE club_player_id = _system_card) <> _count THEN
    RAISE EXCEPTION 'assertion_failed: insufficient balance did not rollback stock';
  END IF;

  PERFORM pg_catalog.set_config('request.jwt.claim.sub', _cap_user::text, true);
  BEGIN
    PERFORM * FROM public.sell_player_to_system(_cap_cards[1]);
    RAISE EXCEPTION 'assertion_failed: cap-exceeding sale succeeded';
  EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS _message = MESSAGE_TEXT;
    IF _message <> 'wallet_balance_cap_exceeded' THEN
      RAISE EXCEPTION 'assertion_failed: expected wallet_balance_cap_exceeded, got %', _message;
    END IF;
  END;
  IF EXISTS (SELECT 1 FROM public.system_market_stock WHERE club_player_id = _cap_cards[1]) THEN
    RAISE EXCEPTION 'assertion_failed: cap failure left stock';
  END IF;

  PERFORM pg_catalog.set_config('request.jwt.claim.sub', _train_user::text, true);
  UPDATE public.club_players SET is_reserved = true WHERE id = _train_cards[1];
  BEGIN
    PERFORM * FROM public.train_club_player(_train_cards[1], 'velocity');
    RAISE EXCEPTION 'assertion_failed: reserved card trained';
  EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS _message = MESSAGE_TEXT;
    IF _message <> 'card_reserved' THEN
      RAISE EXCEPTION 'assertion_failed: expected card_reserved, got %', _message;
    END IF;
  END;
  UPDATE public.club_players SET is_reserved = false WHERE id = _train_cards[1];

  BEGIN
    PERFORM * FROM public.train_club_player(_train_cards[1], 'banana');
    RAISE EXCEPTION 'assertion_failed: invalid attribute trained';
  EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS _message = MESSAGE_TEXT;
    IF _message <> 'attribute_invalid' THEN
      RAISE EXCEPTION 'assertion_failed: expected attribute_invalid, got %', _message;
    END IF;
  END;

  SELECT c.balance_cents INTO _before_balance FROM public.clubs c WHERE c.id = _train_club;
  SELECT result.cost_cents, result.balance_cents, result.progress_before, result.progress_after, result.attribute_before, result.attribute_after
  INTO _result
  FROM public.train_club_player(_train_cards[1], 'velocity') AS result;
  IF _result.cost_cents <> 25 OR _result.balance_cents <> _before_balance - 25 OR _result.progress_before <> 0 OR _result.progress_after <> 1 OR _result.attribute_after <> _result.attribute_before THEN
    RAISE EXCEPTION 'assertion_failed: first training result invalid';
  END IF;

  BEGIN
    PERFORM * FROM public.train_club_player(_train_cards[1], 'velocity');
    RAISE EXCEPTION 'assertion_failed: second same-day training succeeded';
  EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS _message = MESSAGE_TEXT;
    IF _message <> 'training_already_done_today' THEN
      RAISE EXCEPTION 'assertion_failed: expected training_already_done_today, got %', _message;
    END IF;
  END;

  UPDATE public.training_sessions
  SET day = day - 1
  WHERE club_id = _train_club;

  SELECT result.progress_before, result.progress_after, result.attribute_before, result.attribute_after
  INTO _result
  FROM public.train_club_player(_train_cards[1], 'velocity') AS result;
  IF _result.progress_before <> 1 OR _result.progress_after <> 2 OR _result.attribute_after <> _result.attribute_before THEN
    RAISE EXCEPTION 'assertion_failed: second training progression invalid';
  END IF;

  UPDATE public.training_sessions
  SET day = day - 2
  WHERE club_id = _train_club
    AND day = (pg_catalog.now() AT TIME ZONE 'America/Belem')::date;

  SELECT p.velocity, p.overall, p.reference_value_cents
  INTO _before_attr, _before_ovr, _before_ref
  FROM public.club_players cp
  JOIN public.players p ON p.id = cp.player_id
  WHERE cp.id = _train_cards[1];

  SELECT result.progress_before, result.progress_after, result.attribute_before, result.attribute_after, result.overall_before, result.overall_after, result.reference_value_before_cents, result.reference_value_after_cents
  INTO _result
  FROM public.train_club_player(_train_cards[1], 'velocity') AS result;

  SELECT p.velocity, p.overall, p.reference_value_cents
  INTO _after_attr, _after_ovr, _after_ref
  FROM public.club_players cp
  JOIN public.players p ON p.id = cp.player_id
  WHERE cp.id = _train_cards[1];

  IF _result.progress_before <> 2 OR _result.progress_after <> 0 OR _after_attr <> _before_attr + 1 OR _result.attribute_after <> _before_attr + 1 THEN
    RAISE EXCEPTION 'assertion_failed: third training did not increment attribute';
  END IF;
  IF _after_ovr <> public.calculate_player_overall((SELECT p.position FROM public.players p WHERE p.id = (SELECT cp.player_id FROM public.club_players cp WHERE cp.id = _train_cards[1])), _after_attr::smallint, (SELECT p.finishing FROM public.players p WHERE p.id = (SELECT cp.player_id FROM public.club_players cp WHERE cp.id = _train_cards[1])), (SELECT p.passing FROM public.players p WHERE p.id = (SELECT cp.player_id FROM public.club_players cp WHERE cp.id = _train_cards[1])), (SELECT p.dribbling FROM public.players p WHERE p.id = (SELECT cp.player_id FROM public.club_players cp WHERE cp.id = _train_cards[1])), (SELECT p.defending FROM public.players p WHERE p.id = (SELECT cp.player_id FROM public.club_players cp WHERE cp.id = _train_cards[1])), (SELECT p.physical FROM public.players p WHERE p.id = (SELECT cp.player_id FROM public.club_players cp WHERE cp.id = _train_cards[1])), (SELECT p.goalkeeping FROM public.players p WHERE p.id = (SELECT cp.player_id FROM public.club_players cp WHERE cp.id = _train_cards[1])) ) THEN
    RAISE EXCEPTION 'assertion_failed: OVR not recalculated after training';
  END IF;
  IF _after_ref <> public.calculate_reference_value_cents((SELECT p.rarity FROM public.players p WHERE p.id = (SELECT cp.player_id FROM public.club_players cp WHERE cp.id = _train_cards[1])), _after_ovr::smallint, (SELECT p.position FROM public.players p WHERE p.id = (SELECT cp.player_id FROM public.club_players cp WHERE cp.id = _train_cards[1]))) THEN
    RAISE EXCEPTION 'assertion_failed: reference value not recalculated after training';
  END IF;

  UPDATE public.training_sessions
  SET day = day - 3
  WHERE club_id = _train_club
    AND day = (pg_catalog.now() AT TIME ZONE 'America/Belem')::date;
  UPDATE public.players p
  SET velocity = 99
  WHERE p.id = (SELECT cp.player_id FROM public.club_players cp WHERE cp.id = _train_cards[1]);
  SELECT c.balance_cents INTO _before_balance FROM public.clubs c WHERE c.id = _train_club;
  BEGIN
    PERFORM * FROM public.train_club_player(_train_cards[1], 'velocity');
    RAISE EXCEPTION 'assertion_failed: maxed attribute trained';
  EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS _message = MESSAGE_TEXT;
    IF _message <> 'attribute_maxed' THEN
      RAISE EXCEPTION 'assertion_failed: expected attribute_maxed, got %', _message;
    END IF;
  END;
  SELECT c.balance_cents INTO _after_balance FROM public.clubs c WHERE c.id = _train_club;
  IF _after_balance <> _before_balance THEN
    RAISE EXCEPTION 'assertion_failed: maxed attribute debited balance';
  END IF;

  -- Progress follows the permanent card through system sale and repurchase.
  UPDATE public.clubs SET balance_cents = 9000 WHERE id = _train_club;
  UPDATE public.players p
  SET velocity = 50
  WHERE p.id = (SELECT cp.player_id FROM public.club_players cp WHERE cp.id = _train_cards[1]);
  PERFORM pg_catalog.set_config('request.jwt.claim.sub', _train_user::text, true);
  PERFORM * FROM public.sell_player_to_system(_train_cards[1]);
  PERFORM * FROM public.buy_player_from_system(_train_cards[1]);
  IF NOT EXISTS (
    SELECT 1
    FROM public.club_player_attribute_progress cpp
    WHERE cpp.club_player_id = _train_cards[1]
      AND cpp.attribute = 'velocity'
  ) THEN
    RAISE EXCEPTION 'assertion_failed: progress lost after sale and repurchase';
  END IF;

  PERFORM pg_catalog.set_config('request.jwt.claim.sub', _pack_user::text, true);
  SELECT pg_catalog.count(*) INTO _count
  FROM public.open_initial_pack(_pack_club);
  IF _count <> 10 THEN
    RAISE EXCEPTION 'assertion_failed: initial pack did not return 10 rows';
  END IF;
  IF EXISTS (
    SELECT 1
    FROM public.club_players cp
    JOIN public.system_market_stock sms ON sms.club_player_id = cp.id
    WHERE cp.club_id = _pack_club
  ) THEN
    RAISE EXCEPTION 'assertion_failed: initial pack left stock rows for club cards';
  END IF;
  IF EXISTS (
    SELECT cp.player_id
    FROM public.club_players cp
    GROUP BY cp.player_id
    HAVING pg_catalog.count(*) > 1
  ) THEN
    RAISE EXCEPTION 'assertion_failed: initial pack duplicated a card';
  END IF;

  RAISE NOTICE 'player_market_training contract test passed';
END $$;

ROLLBACK;
