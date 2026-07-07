-- =====================================================================
-- BAGREFUT - Fix admin audit atomicity and approved-only game RLS
-- =====================================================================

CREATE OR REPLACE FUNCTION public.is_approved_user(_user_id uuid DEFAULT auth.uid())
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
  SELECT COALESCE(
    EXISTS (
      SELECT 1
      FROM public.profiles p
      WHERE p.id = _user_id
        AND p.status = 'approved'
    ),
    false
  )
$$;

REVOKE ALL ON FUNCTION public.is_approved_user(uuid) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.is_approved_user(uuid) TO authenticated;

DROP FUNCTION IF EXISTS public.admin_set_user_status(uuid, public.user_status, text);

CREATE OR REPLACE FUNCTION public.admin_set_user_status(
  _target_user_id uuid,
  _new_status public.user_status,
  _reason text DEFAULT NULL
)
RETURNS TABLE(
  target_user_id uuid,
  previous_status public.user_status,
  new_status public.user_status,
  audit_log_id uuid,
  changed_at timestamptz
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  _actor_id uuid := auth.uid();
  _actor_profile public.profiles%ROWTYPE;
  _target_profile public.profiles%ROWTYPE;
  _previous_status public.user_status;
  _audit_log_id uuid;
  _changed_at timestamptz := pg_catalog.now();
BEGIN
  IF _actor_id IS NULL THEN
    RAISE EXCEPTION 'unauthenticated';
  END IF;

  IF _target_user_id IS NULL THEN
    RAISE EXCEPTION 'target_profile_not_found';
  END IF;

  IF _new_status IS NULL THEN
    RAISE EXCEPTION 'invalid_status';
  END IF;

  SELECT *
  INTO _actor_profile
  FROM public.profiles
  WHERE id = _actor_id;

  IF _actor_profile.id IS NULL THEN
    RAISE EXCEPTION 'profile_not_found';
  END IF;

  IF _actor_profile.status <> 'approved' THEN
    RAISE EXCEPTION 'profile_not_approved';
  END IF;

  IF NOT public.has_role(_actor_id, 'admin'::public.app_role) THEN
    RAISE EXCEPTION 'forbidden_not_admin';
  END IF;

  SELECT *
  INTO _target_profile
  FROM public.profiles
  WHERE id = _target_user_id
  FOR UPDATE;

  IF _target_profile.id IS NULL THEN
    RAISE EXCEPTION 'target_profile_not_found';
  END IF;

  _previous_status := _target_profile.status;

  UPDATE public.profiles
  SET status = _new_status,
      updated_at = _changed_at
  WHERE id = _target_user_id;

  INSERT INTO public.admin_audit_logs (
    admin_id,
    action,
    target_table,
    target_id,
    payload,
    created_at
  )
  VALUES (
    _actor_id,
    'admin_set_user_status',
    'profiles',
    _target_user_id,
    pg_catalog.jsonb_build_object(
      'actor_user_id', _actor_id,
      'target_user_id', _target_user_id,
      'previous_status', _previous_status,
      'new_status', _new_status,
      'reason', _reason,
      'changed_at', _changed_at
    ),
    _changed_at
  )
  RETURNING id INTO _audit_log_id;

  RETURN QUERY
  SELECT
    _target_user_id,
    _previous_status,
    _new_status,
    _audit_log_id,
    _changed_at;
END;
$$;

REVOKE ALL ON FUNCTION public.admin_set_user_status(uuid, public.user_status, text) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.admin_set_user_status(uuid, public.user_status, text) TO authenticated;

-- Grants: keep direct writes out of RPC-owned tables and remove excess rights.
REVOKE INSERT, UPDATE, DELETE ON public.profiles FROM authenticated;
REVOKE INSERT, UPDATE, DELETE ON public.lineups FROM authenticated;
REVOKE INSERT, UPDATE, DELETE ON public.lineup_players FROM authenticated;
REVOKE INSERT, UPDATE, DELETE ON public.admin_audit_logs FROM authenticated;

REVOKE TRUNCATE, REFERENCES, TRIGGER ON TABLE
  public.profiles,
  public.user_roles,
  public.leagues,
  public.club_badges,
  public.clubs,
  public.players,
  public.club_players,
  public.initial_packs,
  public.initial_pack_items,
  public.wallet_transactions,
  public.seasons,
  public.rounds,
  public.matches,
  public.match_events,
  public.lineups,
  public.lineup_players,
  public.training_sessions,
  public.market_listings,
  public.transfer_offers,
  public.transfer_offer_items,
  public.push_subscriptions,
  public.admin_audit_logs
FROM authenticated;

GRANT SELECT ON public.profiles TO authenticated;
GRANT SELECT ON public.user_roles TO authenticated;
GRANT SELECT ON public.leagues TO authenticated;
GRANT SELECT ON public.club_badges TO authenticated;
GRANT SELECT ON public.clubs TO authenticated;
GRANT SELECT ON public.players TO authenticated;
GRANT SELECT ON public.club_players TO authenticated;
GRANT SELECT ON public.initial_packs TO authenticated;
GRANT SELECT ON public.initial_pack_items TO authenticated;
GRANT SELECT ON public.wallet_transactions TO authenticated;
GRANT SELECT ON public.seasons TO authenticated;
GRANT SELECT ON public.rounds TO authenticated;
GRANT SELECT ON public.matches TO authenticated;
GRANT SELECT ON public.match_events TO authenticated;
GRANT SELECT ON public.lineups TO authenticated;
GRANT SELECT ON public.lineup_players TO authenticated;
GRANT SELECT ON public.training_sessions TO authenticated;
GRANT SELECT ON public.market_listings TO authenticated;
GRANT SELECT ON public.transfer_offers TO authenticated;
GRANT SELECT ON public.transfer_offer_items TO authenticated;
GRANT SELECT, INSERT, DELETE ON public.push_subscriptions TO authenticated;
GRANT SELECT ON public.admin_audit_logs TO authenticated;

-- Profiles and roles.
DROP POLICY IF EXISTS "profiles_self_select" ON public.profiles;
DROP POLICY IF EXISTS "profiles_admin_update" ON public.profiles;

CREATE POLICY "profiles_self_or_approved_admin_read"
ON public.profiles
FOR SELECT
TO authenticated
USING (
  auth.uid() = id
  OR (
    public.is_approved_user(auth.uid())
    AND public.has_role(auth.uid(), 'admin'::public.app_role)
  )
);

CREATE POLICY "profiles_approved_admin_update"
ON public.profiles
FOR UPDATE
TO authenticated
USING (
  public.is_approved_user(auth.uid())
  AND public.has_role(auth.uid(), 'admin'::public.app_role)
)
WITH CHECK (
  public.is_approved_user(auth.uid())
  AND public.has_role(auth.uid(), 'admin'::public.app_role)
);

DROP POLICY IF EXISTS "user_roles_self_select" ON public.user_roles;

CREATE POLICY "user_roles_approved_self_or_admin_read"
ON public.user_roles
FOR SELECT
TO authenticated
USING (
  public.is_approved_user(auth.uid())
  AND (
    auth.uid() = user_id
    OR public.has_role(auth.uid(), 'admin'::public.app_role)
  )
);

-- Global readable game catalogs.
DROP POLICY IF EXISTS "leagues_authenticated_read" ON public.leagues;
CREATE POLICY "leagues_approved_read"
ON public.leagues
FOR SELECT
TO authenticated
USING (public.is_approved_user(auth.uid()));

DROP POLICY IF EXISTS "club_badges_authenticated_read" ON public.club_badges;
CREATE POLICY "club_badges_approved_read"
ON public.club_badges
FOR SELECT
TO authenticated
USING (
  public.is_approved_user(auth.uid())
  AND is_active
);

DROP POLICY IF EXISTS "clubs_authenticated_read" ON public.clubs;
CREATE POLICY "clubs_approved_read"
ON public.clubs
FOR SELECT
TO authenticated
USING (public.is_approved_user(auth.uid()));

DROP POLICY IF EXISTS "players_authenticated_read" ON public.players;
CREATE POLICY "players_approved_read"
ON public.players
FOR SELECT
TO authenticated
USING (public.is_approved_user(auth.uid()));

DROP POLICY IF EXISTS "seasons_authenticated_read" ON public.seasons;
CREATE POLICY "seasons_approved_read"
ON public.seasons
FOR SELECT
TO authenticated
USING (public.is_approved_user(auth.uid()));

DROP POLICY IF EXISTS "rounds_authenticated_read" ON public.rounds;
CREATE POLICY "rounds_approved_read"
ON public.rounds
FOR SELECT
TO authenticated
USING (public.is_approved_user(auth.uid()));

DROP POLICY IF EXISTS "matches_authenticated_read" ON public.matches;
CREATE POLICY "matches_approved_read"
ON public.matches
FOR SELECT
TO authenticated
USING (public.is_approved_user(auth.uid()));

-- Ownership-scoped reads.
DROP POLICY IF EXISTS "club_players_read_own_or_admin" ON public.club_players;
CREATE POLICY "club_players_approved_owner_or_admin_read"
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
    OR public.has_role(auth.uid(), 'admin'::public.app_role)
  )
);

DROP POLICY IF EXISTS "initial_packs_owner_read" ON public.initial_packs;
CREATE POLICY "initial_packs_approved_owner_or_admin_read"
ON public.initial_packs
FOR SELECT
TO authenticated
USING (
  public.is_approved_user(auth.uid())
  AND (
    EXISTS (
      SELECT 1
      FROM public.clubs c
      WHERE c.id = initial_packs.club_id
        AND c.owner_id = auth.uid()
    )
    OR public.has_role(auth.uid(), 'admin'::public.app_role)
  )
);

DROP POLICY IF EXISTS "initial_pack_items_owner_read" ON public.initial_pack_items;
CREATE POLICY "initial_pack_items_approved_owner_or_admin_read"
ON public.initial_pack_items
FOR SELECT
TO authenticated
USING (
  public.is_approved_user(auth.uid())
  AND (
    EXISTS (
      SELECT 1
      FROM public.initial_packs p
      JOIN public.clubs c ON c.id = p.club_id
      WHERE p.id = initial_pack_items.pack_id
        AND c.owner_id = auth.uid()
    )
    OR public.has_role(auth.uid(), 'admin'::public.app_role)
  )
);

DROP POLICY IF EXISTS "wallet_tx_owner_read" ON public.wallet_transactions;
CREATE POLICY "wallet_tx_approved_owner_or_admin_read"
ON public.wallet_transactions
FOR SELECT
TO authenticated
USING (
  public.is_approved_user(auth.uid())
  AND (
    EXISTS (
      SELECT 1
      FROM public.clubs c
      WHERE c.id = wallet_transactions.club_id
        AND c.owner_id = auth.uid()
    )
    OR public.has_role(auth.uid(), 'admin'::public.app_role)
  )
);

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

-- Match events: keep reveal rule for non-admins, require approved status for everyone.
DROP POLICY IF EXISTS "match_events_read_revealed" ON public.match_events;
CREATE POLICY "match_events_approved_read_revealed_or_admin"
ON public.match_events
FOR SELECT
TO authenticated
USING (
  public.is_approved_user(auth.uid())
  AND (
    reveal_at <= pg_catalog.now()
    OR public.has_role(auth.uid(), 'admin'::public.app_role)
  )
);

-- Lineups: preserve owner/admin/released-read semantics, but require approved.
DROP POLICY IF EXISTS "lineups_owner_read" ON public.lineups;
DROP POLICY IF EXISTS "lineups_owner_insert" ON public.lineups;
DROP POLICY IF EXISTS "lineups_owner_update" ON public.lineups;
DROP POLICY IF EXISTS "lineups_owner_admin_or_released_read" ON public.lineups;

CREATE POLICY "lineups_approved_owner_admin_or_released_read"
ON public.lineups
FOR SELECT
TO authenticated
USING (
  public.is_approved_user(auth.uid())
  AND (
    public.has_role(auth.uid(), 'admin'::public.app_role)
    OR EXISTS (
      SELECT 1
      FROM public.clubs c
      WHERE c.id = lineups.club_id
        AND c.owner_id = auth.uid()
    )
    OR EXISTS (
      SELECT 1
      FROM public.rounds r
      WHERE r.id = lineups.round_id
        AND r.lineup_lock_at <= pg_catalog.now()
    )
  )
);

DROP POLICY IF EXISTS "lineup_players_owner_all" ON public.lineup_players;
DROP POLICY IF EXISTS "lineup_players_owner_admin_or_released_read" ON public.lineup_players;

CREATE POLICY "lineup_players_approved_owner_admin_or_released_read"
ON public.lineup_players
FOR SELECT
TO authenticated
USING (
  public.is_approved_user(auth.uid())
  AND EXISTS (
    SELECT 1
    FROM public.lineups l
    JOIN public.clubs c ON c.id = l.club_id
    WHERE l.id = lineup_players.lineup_id
      AND (
        c.owner_id = auth.uid()
        OR public.has_role(auth.uid(), 'admin'::public.app_role)
        OR EXISTS (
          SELECT 1
          FROM public.rounds r
          WHERE r.id = l.round_id
            AND r.lineup_lock_at <= pg_catalog.now()
        )
      )
  )
);

-- Market and transfers.
DROP POLICY IF EXISTS "market_read_all_authenticated" ON public.market_listings;
CREATE POLICY "market_listings_approved_read"
ON public.market_listings
FOR SELECT
TO authenticated
USING (public.is_approved_user(auth.uid()));

DROP POLICY IF EXISTS "offers_participant_read" ON public.transfer_offers;
CREATE POLICY "transfer_offers_approved_participant_or_admin_read"
ON public.transfer_offers
FOR SELECT
TO authenticated
USING (
  public.is_approved_user(auth.uid())
  AND (
    EXISTS (
      SELECT 1
      FROM public.clubs c
      WHERE c.id IN (transfer_offers.from_club_id, transfer_offers.to_club_id)
        AND c.owner_id = auth.uid()
    )
    OR public.has_role(auth.uid(), 'admin'::public.app_role)
  )
);

DROP POLICY IF EXISTS "offer_items_participant_read" ON public.transfer_offer_items;
CREATE POLICY "transfer_offer_items_approved_participant_or_admin_read"
ON public.transfer_offer_items
FOR SELECT
TO authenticated
USING (
  public.is_approved_user(auth.uid())
  AND (
    EXISTS (
      SELECT 1
      FROM public.transfer_offers o
      JOIN public.clubs c ON c.id IN (o.from_club_id, o.to_club_id)
      WHERE o.id = transfer_offer_items.offer_id
        AND c.owner_id = auth.uid()
    )
    OR public.has_role(auth.uid(), 'admin'::public.app_role)
  )
);

-- Push subscriptions: approved users manage only their own subscriptions.
DROP POLICY IF EXISTS "push_owner_read" ON public.push_subscriptions;
DROP POLICY IF EXISTS "push_owner_insert" ON public.push_subscriptions;
DROP POLICY IF EXISTS "push_owner_delete" ON public.push_subscriptions;

CREATE POLICY "push_approved_owner_or_admin_read"
ON public.push_subscriptions
FOR SELECT
TO authenticated
USING (
  public.is_approved_user(auth.uid())
  AND (
    user_id = auth.uid()
    OR public.has_role(auth.uid(), 'admin'::public.app_role)
  )
);

CREATE POLICY "push_approved_owner_insert"
ON public.push_subscriptions
FOR INSERT
TO authenticated
WITH CHECK (
  public.is_approved_user(auth.uid())
  AND user_id = auth.uid()
);

CREATE POLICY "push_approved_owner_delete"
ON public.push_subscriptions
FOR DELETE
TO authenticated
USING (
  public.is_approved_user(auth.uid())
  AND user_id = auth.uid()
);

-- Admin audit logs: direct INSERT remains blocked; only approved admin can read.
DROP POLICY IF EXISTS "audit_admin_read" ON public.admin_audit_logs;

CREATE POLICY "audit_approved_admin_read"
ON public.admin_audit_logs
FOR SELECT
TO authenticated
USING (
  public.is_approved_user(auth.uid())
  AND public.has_role(auth.uid(), 'admin'::public.app_role)
);
