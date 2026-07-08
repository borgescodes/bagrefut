
CREATE OR REPLACE FUNCTION public.open_initial_pack(_club_id uuid)
 RETURNS TABLE(pack_id uuid, club_id uuid, opened_at timestamp with time zone, player_id uuid, slot smallint)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
DECLARE
  _uid uuid := auth.uid();
  _profile public.profiles%ROWTYPE;
  _club public.clubs%ROWTYPE;
  _league public.leagues%ROWTYPE;
  _pack public.initial_packs%ROWTYPE;
  _picked_card_ids uuid[];
  _opened_at timestamptz;
BEGIN
  IF _uid IS NULL THEN
    RAISE EXCEPTION 'unauthenticated';
  END IF;

  SELECT * INTO _profile
  FROM public.profiles p
  WHERE p.id = _uid;

  IF _profile.id IS NULL THEN
    RAISE EXCEPTION 'profile_not_found';
  END IF;
  IF _profile.status <> 'approved' THEN
    RAISE EXCEPTION 'profile_not_approved';
  END IF;

  SELECT * INTO _club
  FROM public.clubs c
  WHERE c.id = _club_id
  FOR UPDATE;

  IF _club.id IS NULL THEN
    RAISE EXCEPTION 'club_not_found';
  END IF;
  IF _club.owner_id <> _uid THEN
    RAISE EXCEPTION 'not_club_owner';
  END IF;

  SELECT * INTO _league
  FROM public.leagues l
  WHERE l.id = _club.league_id;

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
    ORDER BY pg_catalog.random()
    LIMIT 10
    FOR UPDATE OF sms, cp SKIP LOCKED
  )
  INTO _picked_card_ids;

  IF COALESCE(pg_catalog.array_length(_picked_card_ids, 1), 0) <> 10 THEN
    RAISE EXCEPTION 'not_enough_players_available';
  END IF;

  DELETE FROM public.system_market_stock sms
  WHERE sms.club_player_id = ANY(_picked_card_ids);

  UPDATE public.club_players cp
  SET club_id = _club_id,
      acquired_at = pg_catalog.now(),
      is_reserved = false
  WHERE cp.id = ANY(_picked_card_ids)
    AND cp.club_id IS NULL;

  INSERT INTO public.initial_pack_items (pack_id, player_id, slot)
  SELECT _pack.id, cp.player_id, picked.slot::smallint
  FROM pg_catalog.unnest(_picked_card_ids) WITH ORDINALITY AS picked(club_player_id, slot)
  JOIN public.club_players cp ON cp.id = picked.club_player_id;

  UPDATE public.initial_packs ip
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
$function$;
