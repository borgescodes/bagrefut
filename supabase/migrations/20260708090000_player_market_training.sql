-- =====================================================================
-- BAGREFUT - Players, derived OVR/prices, system market, and training
-- =====================================================================

CREATE OR REPLACE FUNCTION public.calculate_player_overall(
  _position public.player_position,
  _velocity smallint,
  _finishing smallint,
  _passing smallint,
  _dribbling smallint,
  _defending smallint,
  _physical smallint,
  _goalkeeping smallint
)
RETURNS smallint
LANGUAGE sql
IMMUTABLE
SET search_path = ''
AS $$
  SELECT CASE _position
    WHEN 'GK'::public.player_position THEN
      pg_catalog.round((_goalkeeping * 55 + _defending * 15 + _physical * 15 + _passing * 10 + _velocity * 5) / 100.0)::smallint
    WHEN 'DEF'::public.player_position THEN
      pg_catalog.round((_defending * 40 + _physical * 25 + _velocity * 15 + _passing * 15 + _dribbling * 5) / 100.0)::smallint
    WHEN 'MID'::public.player_position THEN
      pg_catalog.round((_passing * 30 + _dribbling * 25 + _velocity * 15 + _physical * 15 + _defending * 10 + _finishing * 5) / 100.0)::smallint
    WHEN 'ATA'::public.player_position THEN
      pg_catalog.round((_finishing * 40 + _velocity * 20 + _dribbling * 20 + _physical * 10 + _passing * 10) / 100.0)::smallint
  END
$$;

CREATE OR REPLACE FUNCTION public.calculate_reference_value_cents(
  _rarity public.player_rarity,
  _overall smallint,
  _position public.player_position
)
RETURNS integer
LANGUAGE sql
IMMUTABLE
SET search_path = ''
AS $$
  WITH bands AS (
    SELECT
      CASE _rarity
        WHEN 'peba'::public.player_rarity THEN 40
        WHEN 'paia'::public.player_rarity THEN 60
        WHEN 'pika'::public.player_rarity THEN 75
      END AS overall_min,
      CASE _rarity
        WHEN 'peba'::public.player_rarity THEN 59
        WHEN 'paia'::public.player_rarity THEN 74
        WHEN 'pika'::public.player_rarity THEN 89
      END AS overall_max,
      CASE _rarity
        WHEN 'peba'::public.player_rarity THEN 50
        WHEN 'paia'::public.player_rarity THEN 501
        WHEN 'pika'::public.player_rarity THEN 2501
      END AS price_min,
      CASE _rarity
        WHEN 'peba'::public.player_rarity THEN 500
        WHEN 'paia'::public.player_rarity THEN 2500
        WHEN 'pika'::public.player_rarity THEN 10000
      END AS price_max,
      CASE _position
        WHEN 'GK'::public.player_position THEN 0.90
        WHEN 'DEF'::public.player_position THEN 0.95
        WHEN 'MID'::public.player_position THEN 1.00
        WHEN 'ATA'::public.player_position THEN 1.10
      END AS position_multiplier
  ),
  priced AS (
    SELECT pg_catalog.round(
      (
        price_min
        + (
          (GREATEST(overall_min, LEAST(overall_max, _overall::integer)) - overall_min)::numeric
          / GREATEST(1, overall_max - overall_min)
        ) * (price_max - price_min)
      ) * position_multiplier
    )::integer AS cents,
    price_min,
    price_max
    FROM bands
  )
  SELECT LEAST(10000, GREATEST(price_min, LEAST(price_max, cents)))
  FROM priced
$$;

CREATE OR REPLACE FUNCTION public.training_cost_cents(_rarity public.player_rarity)
RETURNS integer
LANGUAGE sql
IMMUTABLE
SET search_path = ''
AS $$
  SELECT CASE _rarity
    WHEN 'peba'::public.player_rarity THEN 25
    WHEN 'paia'::public.player_rarity THEN 75
    WHEN 'pika'::public.player_rarity THEN 150
  END
$$;

REVOKE ALL ON FUNCTION public.calculate_player_overall(public.player_position, smallint, smallint, smallint, smallint, smallint, smallint, smallint) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.calculate_reference_value_cents(public.player_rarity, smallint, public.player_position) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.training_cost_cents(public.player_rarity) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.calculate_player_overall(public.player_position, smallint, smallint, smallint, smallint, smallint, smallint, smallint) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.calculate_reference_value_cents(public.player_rarity, smallint, public.player_position) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.training_cost_cents(public.player_rarity) TO authenticated, service_role;

CREATE OR REPLACE FUNCTION public.set_player_derived_values()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = ''
AS $$
BEGIN
  NEW.overall := public.calculate_player_overall(
    NEW.position,
    NEW.velocity,
    NEW.finishing,
    NEW.passing,
    NEW.dribbling,
    NEW.defending,
    NEW.physical,
    NEW.goalkeeping
  );
  NEW.reference_value_cents := public.calculate_reference_value_cents(NEW.rarity, NEW.overall, NEW.position);
  RETURN NEW;
END;
$$;

REVOKE ALL ON FUNCTION public.set_player_derived_values() FROM PUBLIC, anon, authenticated;

DROP TRIGGER IF EXISTS trg_players_derive_values ON public.players;
CREATE TRIGGER trg_players_derive_values
  BEFORE INSERT OR UPDATE ON public.players
  FOR EACH ROW EXECUTE FUNCTION public.set_player_derived_values();

WITH sequenced AS (
  SELECT
    p.id,
    p.position,
    p.rarity,
    pg_catalog.row_number() OVER (PARTITION BY p.position ORDER BY p.rarity, p.code) AS position_seq
  FROM public.players p
  WHERE p.code ~ '^(GK|DEF|MID|ATA)[0-9]{2}$'
),
targets AS (
  SELECT
    s.*,
    CASE s.rarity
      WHEN 'peba'::public.player_rarity THEN 40 + ((s.position_seq * 5) % 16)
      WHEN 'paia'::public.player_rarity THEN 60 + ((s.position_seq * 4) % 11)
      WHEN 'pika'::public.player_rarity THEN 75 + ((s.position_seq * 3) % 10)
    END AS target_ovr,
    ((s.position_seq % 5) - 2) AS v
  FROM sequenced s
),
attrs AS (
  SELECT
    t.id,
    CASE t.position
      WHEN 'GK'::public.player_position THEN GREATEST(1, LEAST(99, t.target_ovr - 16 + t.v))
      WHEN 'DEF'::public.player_position THEN GREATEST(1, LEAST(99, t.target_ovr - 5 + t.v))
      WHEN 'MID'::public.player_position THEN GREATEST(1, LEAST(99, t.target_ovr - 5 + t.v))
      WHEN 'ATA'::public.player_position THEN GREATEST(1, LEAST(99, t.target_ovr + 5 + t.v))
    END::smallint AS velocity,
    CASE t.position
      WHEN 'GK'::public.player_position THEN GREATEST(1, LEAST(99, 5 + (t.position_seq % 10)))
      WHEN 'DEF'::public.player_position THEN GREATEST(1, LEAST(99, t.target_ovr - 16 + ((t.position_seq * 2) % 5) - 2))
      WHEN 'MID'::public.player_position THEN GREATEST(1, LEAST(99, t.target_ovr - 8 + ((t.position_seq * 2) % 5) - 2))
      WHEN 'ATA'::public.player_position THEN GREATEST(1, LEAST(99, t.target_ovr + 8 + ((t.position_seq * 2) % 5) - 2))
    END::smallint AS finishing,
    CASE t.position
      WHEN 'GK'::public.player_position THEN GREATEST(1, LEAST(99, t.target_ovr - 14 + ((t.position_seq * 3) % 5) - 2))
      WHEN 'DEF'::public.player_position THEN GREATEST(1, LEAST(99, t.target_ovr - 5 + ((t.position_seq * 3) % 5) - 2))
      WHEN 'MID'::public.player_position THEN GREATEST(1, LEAST(99, t.target_ovr + 7 + ((t.position_seq * 3) % 5) - 2))
      WHEN 'ATA'::public.player_position THEN GREATEST(1, LEAST(99, t.target_ovr - 8 + ((t.position_seq * 3) % 5) - 2))
    END::smallint AS passing,
    CASE t.position
      WHEN 'GK'::public.player_position THEN GREATEST(1, LEAST(99, 7 + ((t.position_seq * 4) % 10)))
      WHEN 'DEF'::public.player_position THEN GREATEST(1, LEAST(99, t.target_ovr - 10 + ((t.position_seq * 4) % 5) - 2))
      WHEN 'MID'::public.player_position THEN GREATEST(1, LEAST(99, t.target_ovr + 6 + ((t.position_seq * 4) % 5) - 2))
      WHEN 'ATA'::public.player_position THEN GREATEST(1, LEAST(99, t.target_ovr + 5 + ((t.position_seq * 4) % 5) - 2))
    END::smallint AS dribbling,
    CASE t.position
      WHEN 'GK'::public.player_position THEN GREATEST(1, LEAST(99, t.target_ovr - 10 + ((t.position_seq * 5) % 5) - 2))
      WHEN 'DEF'::public.player_position THEN GREATEST(1, LEAST(99, t.target_ovr + 6 + ((t.position_seq * 5) % 5) - 2))
      WHEN 'MID'::public.player_position THEN GREATEST(1, LEAST(99, t.target_ovr - 8 + ((t.position_seq * 5) % 5) - 2))
      WHEN 'ATA'::public.player_position THEN GREATEST(1, LEAST(99, t.target_ovr - 16 + ((t.position_seq * 5) % 5) - 2))
    END::smallint AS defending,
    CASE t.position
      WHEN 'GK'::public.player_position THEN GREATEST(1, LEAST(99, t.target_ovr - 8 + ((t.position_seq * 6) % 5) - 2))
      WHEN 'DEF'::public.player_position THEN GREATEST(1, LEAST(99, t.target_ovr + 4 + ((t.position_seq * 6) % 5) - 2))
      WHEN 'MID'::public.player_position THEN GREATEST(1, LEAST(99, t.target_ovr - 5 + ((t.position_seq * 6) % 5) - 2))
      WHEN 'ATA'::public.player_position THEN GREATEST(1, LEAST(99, t.target_ovr - 8 + ((t.position_seq * 6) % 5) - 2))
    END::smallint AS physical,
    CASE t.position
      WHEN 'GK'::public.player_position THEN GREATEST(1, LEAST(99, t.target_ovr + 12 + t.v))
      ELSE GREATEST(1, LEAST(99, 5 + (t.position_seq % 12)))
    END::smallint AS goalkeeping
  FROM targets t
)
UPDATE public.players p
SET velocity = a.velocity,
    finishing = a.finishing,
    passing = a.passing,
    dribbling = a.dribbling,
    defending = a.defending,
    physical = a.physical,
    goalkeeping = a.goalkeeping
FROM attrs a
WHERE p.id = a.id;

ALTER TABLE public.club_players
  ALTER COLUMN club_id DROP NOT NULL;

CREATE TABLE IF NOT EXISTS public.system_market_stock (
  club_player_id uuid PRIMARY KEY REFERENCES public.club_players(id) ON DELETE CASCADE,
  acquired_from_club_id uuid NULL REFERENCES public.clubs(id) ON DELETE SET NULL,
  acquired_price_cents integer NOT NULL DEFAULT 0 CHECK (acquired_price_cents >= 0 AND acquired_price_cents <= 10000),
  acquired_at timestamptz NOT NULL DEFAULT pg_catalog.now()
);

GRANT ALL ON public.system_market_stock TO service_role;
REVOKE ALL ON public.system_market_stock FROM PUBLIC, anon, authenticated;
GRANT SELECT ON public.system_market_stock TO authenticated;
ALTER TABLE public.system_market_stock ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "system_market_stock_approved_read" ON public.system_market_stock;
CREATE POLICY "system_market_stock_approved_read"
ON public.system_market_stock
FOR SELECT
TO authenticated
USING (
  public.is_approved_user(auth.uid())
  OR (
    public.is_approved_user(auth.uid())
    AND public.has_role(auth.uid(), 'admin'::public.app_role)
  )
);

INSERT INTO public.club_players (club_id, player_id, acquired_at, is_reserved)
SELECT NULL, p.id, pg_catalog.now(), false
FROM public.players p
WHERE NOT EXISTS (
  SELECT 1
  FROM public.club_players cp
  WHERE cp.player_id = p.id
);

INSERT INTO public.system_market_stock (club_player_id, acquired_from_club_id, acquired_price_cents)
SELECT cp.id, NULL, 0
FROM public.club_players cp
WHERE cp.club_id IS NULL
ON CONFLICT (club_player_id) DO NOTHING;

CREATE OR REPLACE FUNCTION public.create_system_card_for_player()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  _club_player_id uuid;
BEGIN
  INSERT INTO public.club_players (club_id, player_id, acquired_at, is_reserved)
  VALUES (NULL, NEW.id, pg_catalog.now(), false)
  RETURNING id INTO _club_player_id;

  INSERT INTO public.system_market_stock (club_player_id, acquired_from_club_id, acquired_price_cents)
  VALUES (_club_player_id, NULL, 0);

  RETURN NEW;
END;
$$;

REVOKE ALL ON FUNCTION public.create_system_card_for_player() FROM PUBLIC, anon, authenticated;

DROP TRIGGER IF EXISTS trg_players_create_system_card ON public.players;
CREATE TRIGGER trg_players_create_system_card
  AFTER INSERT ON public.players
  FOR EACH ROW EXECUTE FUNCTION public.create_system_card_for_player();

CREATE OR REPLACE FUNCTION public.enforce_system_stock_invariant()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = ''
AS $$
DECLARE
  _club_player_id uuid;
  _club_id uuid;
  _has_stock boolean;
BEGIN
  IF TG_TABLE_NAME = 'system_market_stock' THEN
    _club_player_id := COALESCE(NEW.club_player_id, OLD.club_player_id);
  ELSE
    _club_player_id := COALESCE(NEW.id, OLD.id);
  END IF;

  SELECT cp.club_id
  INTO _club_id
  FROM public.club_players cp
  WHERE cp.id = _club_player_id;

  IF NOT FOUND THEN
    RETURN NULL;
  END IF;

  SELECT EXISTS (
    SELECT 1
    FROM public.system_market_stock sms
    WHERE sms.club_player_id = _club_player_id
  )
  INTO _has_stock;

  IF (_club_id IS NULL AND NOT _has_stock) OR (_club_id IS NOT NULL AND _has_stock) THEN
    RAISE EXCEPTION 'system_stock_invariant_violation';
  END IF;

  RETURN NULL;
END;
$$;

REVOKE ALL ON FUNCTION public.enforce_system_stock_invariant() FROM PUBLIC, anon, authenticated;

DROP TRIGGER IF EXISTS trg_club_players_stock_invariant ON public.club_players;
CREATE CONSTRAINT TRIGGER trg_club_players_stock_invariant
  AFTER INSERT OR UPDATE OF club_id OR DELETE ON public.club_players
  DEFERRABLE INITIALLY DEFERRED
  FOR EACH ROW EXECUTE FUNCTION public.enforce_system_stock_invariant();

DROP TRIGGER IF EXISTS trg_system_market_stock_invariant ON public.system_market_stock;
CREATE CONSTRAINT TRIGGER trg_system_market_stock_invariant
  AFTER INSERT OR UPDATE OR DELETE ON public.system_market_stock
  DEFERRABLE INITIALLY DEFERRED
  FOR EACH ROW EXECUTE FUNCTION public.enforce_system_stock_invariant();

DROP POLICY IF EXISTS "club_players_approved_owner_or_admin_read" ON public.club_players;
DROP POLICY IF EXISTS "club_players_read_own_or_admin" ON public.club_players;
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
      )
    )
    OR public.has_role(auth.uid(), 'admin'::public.app_role)
  )
);

DROP FUNCTION IF EXISTS public.open_initial_pack(uuid);

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

REVOKE ALL ON FUNCTION public.open_initial_pack(uuid) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.open_initial_pack(uuid) TO authenticated;

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

  SELECT * INTO _profile FROM public.profiles WHERE id = _uid;
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

  IF _club.balance_cents + _price > 10000 THEN
    RAISE EXCEPTION 'wallet_balance_cap_exceeded';
  END IF;

  UPDATE public.club_players
  SET club_id = NULL,
      acquired_at = pg_catalog.now(),
      is_reserved = false
  WHERE id = _card.id;

  INSERT INTO public.system_market_stock (club_player_id, acquired_from_club_id, acquired_price_cents)
  VALUES (_card.id, _club.id, _price);

  _new_balance := public._credit_wallet(_club.id, _price, 'system_sale', 'club_players', _card.id, 'venda ao sistema');
  _new_roster_size := _new_roster_size - 1;

  RETURN QUERY
  SELECT _card.id, _player.id, _price, _new_balance, _new_roster_size;
END;
$$;

REVOKE ALL ON FUNCTION public.sell_player_to_system(uuid) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.sell_player_to_system(uuid) TO authenticated;

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

  SELECT * INTO _profile FROM public.profiles WHERE id = _uid;
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

  IF _new_roster_size >= 15 THEN
    RAISE EXCEPTION 'roster_maximum_reached';
  END IF;

  _price := _player.reference_value_cents;
  _new_balance := public._debit_wallet(_club.id, _price, 'system_purchase', 'club_players', _card.id, 'compra do sistema');

  DELETE FROM public.system_market_stock
  WHERE club_player_id = _card.id;

  UPDATE public.club_players
  SET club_id = _club.id,
      acquired_at = pg_catalog.now(),
      is_reserved = false
  WHERE id = _card.id;

  _new_roster_size := _new_roster_size + 1;

  RETURN QUERY
  SELECT _card.id, _player.id, _price, _new_balance, _new_roster_size;
END;
$$;

REVOKE ALL ON FUNCTION public.buy_player_from_system(uuid) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.buy_player_from_system(uuid) TO authenticated;

ALTER TABLE public.training_sessions
  ADD COLUMN IF NOT EXISTS progress_before smallint,
  ADD COLUMN IF NOT EXISTS progress_after smallint,
  ADD COLUMN IF NOT EXISTS attribute_before smallint,
  ADD COLUMN IF NOT EXISTS attribute_after smallint,
  ADD COLUMN IF NOT EXISTS overall_before smallint,
  ADD COLUMN IF NOT EXISTS overall_after smallint,
  ADD COLUMN IF NOT EXISTS reference_value_before_cents integer,
  ADD COLUMN IF NOT EXISTS reference_value_after_cents integer;

CREATE TABLE IF NOT EXISTS public.club_player_attribute_progress (
  club_player_id uuid NOT NULL REFERENCES public.club_players(id) ON DELETE CASCADE,
  attribute text NOT NULL CHECK (attribute IN ('velocity','finishing','passing','dribbling','defending','physical','goalkeeping')),
  progress smallint NOT NULL DEFAULT 0 CHECK (progress BETWEEN 0 AND 2),
  updated_at timestamptz NOT NULL DEFAULT pg_catalog.now(),
  PRIMARY KEY (club_player_id, attribute)
);

DROP TRIGGER IF EXISTS trg_club_player_attribute_progress_updated_at ON public.club_player_attribute_progress;
CREATE TRIGGER trg_club_player_attribute_progress_updated_at
  BEFORE UPDATE ON public.club_player_attribute_progress
  FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();

GRANT ALL ON public.club_player_attribute_progress TO service_role;
REVOKE ALL ON public.club_player_attribute_progress FROM PUBLIC, anon, authenticated;
GRANT SELECT ON public.club_player_attribute_progress TO authenticated;
ALTER TABLE public.club_player_attribute_progress ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "club_player_attribute_progress_approved_owner_or_admin_read" ON public.club_player_attribute_progress;
CREATE POLICY "club_player_attribute_progress_approved_owner_or_admin_read"
ON public.club_player_attribute_progress
FOR SELECT
TO authenticated
USING (
  public.is_approved_user(auth.uid())
  AND (
    EXISTS (
      SELECT 1
      FROM public.club_players cp
      JOIN public.clubs c ON c.id = cp.club_id
      WHERE cp.id = club_player_attribute_progress.club_player_id
        AND c.owner_id = auth.uid()
    )
    OR public.has_role(auth.uid(), 'admin'::public.app_role)
  )
);

DROP POLICY IF EXISTS "training_approved_owner_or_admin_read" ON public.training_sessions;
DROP POLICY IF EXISTS "training_owner_read" ON public.training_sessions;
CREATE POLICY "training_approved_owner_or_admin_read"
ON public.training_sessions
FOR SELECT
TO authenticated
USING (
  public.is_approved_user(auth.uid())
  AND (
    EXISTS (
      SELECT 1
      FROM public.clubs c
      WHERE c.id = training_sessions.club_id
        AND c.owner_id = auth.uid()
    )
    OR public.has_role(auth.uid(), 'admin'::public.app_role)
  )
);

REVOKE INSERT, UPDATE, DELETE, TRUNCATE, REFERENCES, TRIGGER ON TABLE public.training_sessions FROM authenticated;
GRANT SELECT ON public.training_sessions TO authenticated;

CREATE OR REPLACE FUNCTION public.train_club_player(
  _club_player_id uuid,
  _attribute text
)
RETURNS TABLE(
  session_id uuid,
  club_player_id uuid,
  player_id uuid,
  attribute text,
  cost_cents integer,
  balance_cents integer,
  progress_before smallint,
  progress_after smallint,
  attribute_before smallint,
  attribute_after smallint,
  overall_before smallint,
  overall_after smallint,
  reference_value_before_cents integer,
  reference_value_after_cents integer
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
  _day date := (pg_catalog.now() AT TIME ZONE 'America/Belem')::date;
  _cost integer;
  _progress_before smallint;
  _progress_after smallint;
  _attribute_before smallint;
  _attribute_after smallint;
  _overall_before smallint;
  _overall_after smallint;
  _ref_before integer;
  _ref_after integer;
  _session_id uuid;
  _new_balance integer;
BEGIN
  IF _uid IS NULL THEN
    RAISE EXCEPTION 'unauthenticated';
  END IF;

  SELECT * INTO _profile FROM public.profiles WHERE id = _uid;
  IF _profile.id IS NULL OR _profile.status <> 'approved' THEN
    RAISE EXCEPTION 'profile_not_approved';
  END IF;

  IF _attribute NOT IN ('velocity','finishing','passing','dribbling','defending','physical','goalkeeping') THEN
    RAISE EXCEPTION 'attribute_invalid';
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

  IF _card.club_id IS NULL THEN
    RAISE EXCEPTION 'player_not_owned';
  END IF;

  IF _card.is_reserved THEN
    RAISE EXCEPTION 'card_reserved';
  END IF;

  SELECT * INTO _player
  FROM public.players
  WHERE id = _card.player_id
  FOR UPDATE;

  _overall_before := _player.overall;
  _ref_before := _player.reference_value_cents;
  _attribute_before := CASE _attribute
    WHEN 'velocity' THEN _player.velocity
    WHEN 'finishing' THEN _player.finishing
    WHEN 'passing' THEN _player.passing
    WHEN 'dribbling' THEN _player.dribbling
    WHEN 'defending' THEN _player.defending
    WHEN 'physical' THEN _player.physical
    WHEN 'goalkeeping' THEN _player.goalkeeping
  END;

  IF _attribute_before >= 99 THEN
    RAISE EXCEPTION 'attribute_maxed';
  END IF;

  IF EXISTS (
    SELECT 1
    FROM public.training_sessions ts
    WHERE ts.club_id = _club.id
      AND ts.day = _day
    FOR UPDATE
  ) THEN
    RAISE EXCEPTION 'training_already_done_today';
  END IF;

  INSERT INTO public.club_player_attribute_progress (club_player_id, attribute, progress)
  VALUES (_card.id, _attribute, 0)
  ON CONFLICT (club_player_id, attribute) DO NOTHING;

  SELECT progress INTO _progress_before
  FROM public.club_player_attribute_progress
  WHERE club_player_id = _card.id
    AND attribute = _attribute
  FOR UPDATE;

  _cost := public.training_cost_cents(_player.rarity);
  _progress_after := ((_progress_before + 1) % 3)::smallint;
  _attribute_after := _attribute_before;

  INSERT INTO public.training_sessions (
    club_id,
    club_player_id,
    attribute,
    cost_cents,
    day,
    progress_delta,
    progress_before,
    progress_after,
    attribute_before,
    overall_before,
    reference_value_before_cents
  )
  VALUES (
    _club.id,
    _card.id,
    _attribute,
    _cost,
    _day,
    1,
    _progress_before,
    _progress_after,
    _attribute_before,
    _overall_before,
    _ref_before
  )
  RETURNING id INTO _session_id;

  _new_balance := public._debit_wallet(_club.id, _cost, 'training_cost', 'training_sessions', _session_id, 'treino diario');

  UPDATE public.club_player_attribute_progress
  SET progress = _progress_after,
      updated_at = pg_catalog.now()
  WHERE club_player_id = _card.id
    AND attribute = _attribute;

  IF _progress_after = 0 THEN
    _attribute_after := _attribute_before + 1;
    UPDATE public.players p
    SET velocity = CASE WHEN _attribute = 'velocity' THEN _attribute_after ELSE p.velocity END,
        finishing = CASE WHEN _attribute = 'finishing' THEN _attribute_after ELSE p.finishing END,
        passing = CASE WHEN _attribute = 'passing' THEN _attribute_after ELSE p.passing END,
        dribbling = CASE WHEN _attribute = 'dribbling' THEN _attribute_after ELSE p.dribbling END,
        defending = CASE WHEN _attribute = 'defending' THEN _attribute_after ELSE p.defending END,
        physical = CASE WHEN _attribute = 'physical' THEN _attribute_after ELSE p.physical END,
        goalkeeping = CASE WHEN _attribute = 'goalkeeping' THEN _attribute_after ELSE p.goalkeeping END
    WHERE p.id = _player.id;
  END IF;

  SELECT * INTO _player
  FROM public.players
  WHERE id = _player.id;

  _overall_after := _player.overall;
  _ref_after := _player.reference_value_cents;

  IF _progress_after <> 0 THEN
    _attribute_after := _attribute_before;
  END IF;

  UPDATE public.training_sessions
  SET progress_after = _progress_after,
      attribute_after = _attribute_after,
      overall_after = _overall_after,
      reference_value_after_cents = _ref_after
  WHERE id = _session_id;

  RETURN QUERY
  SELECT
    _session_id,
    _card.id,
    _player.id,
    _attribute,
    _cost,
    _new_balance,
    _progress_before,
    _progress_after,
    _attribute_before,
    _attribute_after,
    _overall_before,
    _overall_after,
    _ref_before,
    _ref_after;
END;
$$;

REVOKE ALL ON FUNCTION public.train_club_player(uuid, text) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.train_club_player(uuid, text) TO authenticated;
