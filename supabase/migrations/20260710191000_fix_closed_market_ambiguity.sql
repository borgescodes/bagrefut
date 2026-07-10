-- =====================================================================
-- BAGREFUT - Fix PL/pgSQL ambiguity in closed market RPCs
-- Forward-only corrective migration.
-- Requires: 20260710190000_closed_market_economy.sql
-- =====================================================================

-- RETURNS TABLE output names are PL/pgSQL variables. Every overlapping
-- table column below is explicitly qualified to avoid error 42702.

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
  FROM public.initial_packs ip
  WHERE ip.club_id = _club_id
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

  UPDATE public.initial_packs AS ip
  SET opened_at = pg_catalog.now()
  WHERE ip.id = _pack.id
    AND ip.opened_at IS NULL
  RETURNING ip.opened_at INTO _opened_at;

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
  FROM public.system_market_stock sms
  WHERE sms.club_player_id = _card.id
    AND sms.is_market_eligible
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

  DELETE FROM public.system_market_stock sms
  WHERE sms.club_player_id = _card.id
    AND sms.is_market_eligible;

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
