-- Amplia o retorno das RPCs de mercado/trocas com player_code (players.code),
-- a chave técnica do asset de imagem. Nenhuma regra, filtro, grant ou política
-- muda: somente a coluna extra no retorno.
--
-- list_market_listings e get_trade_target_roster mudam o shape de RETURNS
-- TABLE, então precisam de DROP + CREATE (idempotente via IF EXISTS).
-- Segurança preservada: SECURITY DEFINER, SET search_path = '', REVOKE de
-- PUBLIC/anon e GRANT somente para authenticated, como na migration original.

DROP FUNCTION IF EXISTS public.list_market_listings(
  public.player_position, public.player_rarity, integer, integer, integer
);

CREATE FUNCTION public.list_market_listings(
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
  player_code text,
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
    p.code,
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

REVOKE ALL ON FUNCTION public.list_market_listings(
  public.player_position, public.player_rarity, integer, integer, integer
) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.list_market_listings(
  public.player_position, public.player_rarity, integer, integer, integer
) TO authenticated;

DROP FUNCTION IF EXISTS public.get_trade_target_roster(uuid);

CREATE FUNCTION public.get_trade_target_roster(_club_id uuid)
RETURNS TABLE(
  club_player_id uuid,
  player_id uuid,
  player_code text,
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
    cp.id, p.id, p.code, p.name, p.position, p.rarity, p.sector, p.overall,
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

REVOKE ALL ON FUNCTION public.get_trade_target_roster(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.get_trade_target_roster(uuid) TO authenticated;

-- list_my_transfer_offers devolve as cartas como jsonb; o shape do RETURNS
-- TABLE não muda, então CREATE OR REPLACE basta. Só adiciona 'player_code'.
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
          'player_code', p.code,
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
          'player_code', p.code,
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

REVOKE ALL ON FUNCTION public.list_my_transfer_offers() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.list_my_transfer_offers() TO authenticated;
