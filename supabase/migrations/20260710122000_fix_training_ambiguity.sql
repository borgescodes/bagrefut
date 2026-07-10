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

SELECT p.*
INTO _profile
FROM public.profiles p
WHERE p.id = _uid;

IF _profile.id IS NULL OR _profile.status <> 'approved' THEN
    RAISE EXCEPTION 'profile_not_approved';
END IF;

  IF _attribute NOT IN (
    'velocity',
    'finishing',
    'passing',
    'dribbling',
    'defending',
    'physical',
    'goalkeeping'
  ) THEN
    RAISE EXCEPTION 'attribute_invalid';
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

IF _card.id IS NULL OR _card.club_id <> _club.id THEN
    RAISE EXCEPTION 'player_not_owned';
END IF;

  IF _card.club_id IS NULL THEN
    RAISE EXCEPTION 'player_not_owned';
END IF;

  IF _card.is_reserved THEN
    RAISE EXCEPTION 'card_reserved';
END IF;

SELECT p.*
INTO _player
FROM public.players p
WHERE p.id = _card.player_id
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

INSERT INTO public.club_player_attribute_progress (
    club_player_id,
    attribute,
    progress
)
VALUES (
           _card.id,
           _attribute,
           0
       )
    ON CONFLICT ON CONSTRAINT club_player_attribute_progress_pkey
    DO NOTHING;

SELECT cpap.progress
INTO _progress_before
FROM public.club_player_attribute_progress cpap
WHERE cpap.club_player_id = _card.id
  AND cpap.attribute = _attribute
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
    RETURNING public.training_sessions.id
INTO _session_id;

_new_balance := public._debit_wallet(
    _club.id,
    _cost,
    'training_cost',
    'training_sessions',
    _session_id,
    'treino diario'
  );

UPDATE public.club_player_attribute_progress cpap
SET progress = _progress_after,
    updated_at = pg_catalog.now()
WHERE cpap.club_player_id = _card.id
  AND cpap.attribute = _attribute;

IF _progress_after = 0 THEN
    _attribute_after := _attribute_before + 1;

UPDATE public.players p
SET velocity = CASE
                   WHEN _attribute = 'velocity' THEN _attribute_after
                   ELSE p.velocity
    END,
    finishing = CASE
                    WHEN _attribute = 'finishing' THEN _attribute_after
                    ELSE p.finishing
        END,
    passing = CASE
                  WHEN _attribute = 'passing' THEN _attribute_after
                  ELSE p.passing
        END,
    dribbling = CASE
                    WHEN _attribute = 'dribbling' THEN _attribute_after
                    ELSE p.dribbling
        END,
    defending = CASE
                    WHEN _attribute = 'defending' THEN _attribute_after
                    ELSE p.defending
        END,
    physical = CASE
                   WHEN _attribute = 'physical' THEN _attribute_after
                   ELSE p.physical
        END,
    goalkeeping = CASE
                      WHEN _attribute = 'goalkeeping' THEN _attribute_after
                      ELSE p.goalkeeping
        END
WHERE p.id = _player.id;
END IF;

SELECT p.*
INTO _player
FROM public.players p
WHERE p.id = _player.id;

_overall_after := _player.overall;
  _ref_after := _player.reference_value_cents;

  IF _progress_after <> 0 THEN
    _attribute_after := _attribute_before;
END IF;

UPDATE public.training_sessions ts
SET progress_after = _progress_after,
    attribute_after = _attribute_after,
    overall_after = _overall_after,
    reference_value_after_cents = _ref_after
WHERE ts.id = _session_id;

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

REVOKE ALL ON FUNCTION public.train_club_player(uuid, text)
    FROM PUBLIC, anon, authenticated;

GRANT EXECUTE ON FUNCTION public.train_club_player(uuid, text)
TO authenticated;