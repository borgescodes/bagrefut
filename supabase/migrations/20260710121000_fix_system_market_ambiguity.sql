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

SELECT p.*
INTO _profile
FROM public.profiles p
WHERE p.id = _uid;

IF _profile.id IS NULL OR _profile.status <> 'approved' THEN
    RAISE EXCEPTION 'profile_not_approved';
END IF;

SELECT c.*
INTO _club
FROM public.clubs c
WHERE c.owner_id = _uid
    FOR UPDATE;

IF _club.id IS NULL THEN
    RAISE EXCEPTION 'club_not_found';
END IF;

SELECT cp.*
INTO _card
FROM public.club_players cp
WHERE cp.id = _club_player_id
    FOR UPDATE;

IF _card.id IS NULL OR _card.club_id IS NOT NULL THEN
    RAISE EXCEPTION 'player_not_in_system_stock';
END IF;

SELECT sms.*
INTO _stock
FROM public.system_market_stock sms
WHERE sms.club_player_id = _card.id
    FOR UPDATE;

IF _stock.club_player_id IS NULL THEN
    RAISE EXCEPTION 'player_not_in_system_stock';
END IF;

SELECT p.*
INTO _player
FROM public.players p
WHERE p.id = _card.player_id
    FOR UPDATE;

SELECT pg_catalog.count(*)::integer
INTO _new_roster_size
FROM public.club_players cp
WHERE cp.club_id = _club.id;

IF _new_roster_size >= 15 THEN
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
WHERE sms.club_player_id = _card.id;

UPDATE public.club_players cp
SET club_id = _club.id,
    acquired_at = pg_catalog.now(),
    is_reserved = false
WHERE cp.id = _card.id;

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