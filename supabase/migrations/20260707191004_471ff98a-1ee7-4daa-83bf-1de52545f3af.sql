
-- =====================================================================
-- BAGREFUT - Migration 004: seasons, rounds, matches, lineups, training, market, push, audit
-- =====================================================================

-- ---------- SEASONS ----------
CREATE TABLE public.seasons (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  league_id uuid NOT NULL REFERENCES public.leagues(id) ON DELETE RESTRICT,
  season_number int NOT NULL,
  status text NOT NULL DEFAULT 'scheduled' CHECK (status IN ('scheduled','active','finished')),
  started_at timestamptz,
  finished_at timestamptz,
  seed bigint NOT NULL DEFAULT (floor(random()*9223372036854775807))::bigint,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE (league_id, season_number)
);
GRANT SELECT ON public.seasons TO authenticated;
GRANT ALL ON public.seasons TO service_role;
ALTER TABLE public.seasons ENABLE ROW LEVEL SECURITY;
CREATE TRIGGER trg_seasons_updated_at BEFORE UPDATE ON public.seasons FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();
CREATE POLICY "seasons_authenticated_read" ON public.seasons FOR SELECT TO authenticated USING (true);

-- ---------- ROUNDS ----------
CREATE TABLE public.rounds (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  season_id uuid NOT NULL REFERENCES public.seasons(id) ON DELETE CASCADE,
  round_number smallint NOT NULL CHECK (round_number BETWEEN 1 AND 10),
  lineup_lock_at timestamptz NOT NULL,
  starts_at timestamptz NOT NULL,
  ends_at timestamptz NOT NULL,
  is_processed boolean NOT NULL DEFAULT false,
  UNIQUE (season_id, round_number)
);
GRANT SELECT ON public.rounds TO authenticated;
GRANT ALL ON public.rounds TO service_role;
ALTER TABLE public.rounds ENABLE ROW LEVEL SECURITY;
CREATE POLICY "rounds_authenticated_read" ON public.rounds FOR SELECT TO authenticated USING (true);

-- ---------- MATCHES ----------
CREATE TABLE public.matches (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  round_id uuid NOT NULL REFERENCES public.rounds(id) ON DELETE CASCADE,
  home_club_id uuid NOT NULL REFERENCES public.clubs(id) ON DELETE RESTRICT,
  away_club_id uuid NOT NULL REFERENCES public.clubs(id) ON DELETE RESTRICT,
  home_goals smallint NOT NULL DEFAULT 0 CHECK (home_goals >= 0),
  away_goals smallint NOT NULL DEFAULT 0 CHECK (away_goals >= 0),
  status public.match_status NOT NULL DEFAULT 'scheduled',
  seed bigint,
  simulated_at timestamptz,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT matches_distinct_clubs CHECK (home_club_id <> away_club_id)
);
CREATE INDEX idx_matches_round ON public.matches(round_id);
CREATE INDEX idx_matches_home ON public.matches(home_club_id);
CREATE INDEX idx_matches_away ON public.matches(away_club_id);
GRANT SELECT ON public.matches TO authenticated;
GRANT ALL ON public.matches TO service_role;
ALTER TABLE public.matches ENABLE ROW LEVEL SECURITY;
CREATE TRIGGER trg_matches_updated_at BEFORE UPDATE ON public.matches FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();
CREATE POLICY "matches_authenticated_read" ON public.matches FOR SELECT TO authenticated USING (true);

-- ---------- MATCH EVENTS ----------
CREATE TABLE public.match_events (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  match_id uuid NOT NULL REFERENCES public.matches(id) ON DELETE CASCADE,
  minute smallint NOT NULL CHECK (minute BETWEEN 0 AND 120),
  reveal_at timestamptz NOT NULL,
  event_type public.match_event_type NOT NULL,
  club_id uuid REFERENCES public.clubs(id) ON DELETE RESTRICT,
  player_id uuid REFERENCES public.players(id) ON DELETE RESTRICT,
  meta jsonb NOT NULL DEFAULT '{}'::jsonb,
  created_at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX idx_match_events_match ON public.match_events(match_id, minute);
CREATE INDEX idx_match_events_reveal ON public.match_events(reveal_at);
GRANT SELECT ON public.match_events TO authenticated;
GRANT ALL ON public.match_events TO service_role;
ALTER TABLE public.match_events ENABLE ROW LEVEL SECURITY;
-- Only events whose reveal window has arrived are visible to non-admin.
CREATE POLICY "match_events_read_revealed" ON public.match_events
  FOR SELECT TO authenticated
  USING (reveal_at <= now() OR public.has_role(auth.uid(), 'admin'));

-- ---------- LINEUPS ----------
CREATE TABLE public.lineups (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  club_id uuid NOT NULL REFERENCES public.clubs(id) ON DELETE CASCADE,
  round_id uuid NOT NULL REFERENCES public.rounds(id) ON DELETE CASCADE,
  formation public.formation NOT NULL,
  play_style public.play_style NOT NULL DEFAULT 'balanced',
  is_auto_generated boolean NOT NULL DEFAULT false,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE (club_id, round_id)
);
GRANT SELECT, INSERT, UPDATE ON public.lineups TO authenticated;
GRANT ALL ON public.lineups TO service_role;
ALTER TABLE public.lineups ENABLE ROW LEVEL SECURITY;
CREATE TRIGGER trg_lineups_updated_at BEFORE UPDATE ON public.lineups FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();

CREATE POLICY "lineups_owner_read" ON public.lineups FOR SELECT TO authenticated
  USING (EXISTS (SELECT 1 FROM public.clubs c WHERE c.id = club_id AND c.owner_id = auth.uid())
         OR public.has_role(auth.uid(), 'admin'));
CREATE POLICY "lineups_owner_insert" ON public.lineups FOR INSERT TO authenticated
  WITH CHECK (EXISTS (SELECT 1 FROM public.clubs c WHERE c.id = club_id AND c.owner_id = auth.uid()));
CREATE POLICY "lineups_owner_update" ON public.lineups FOR UPDATE TO authenticated
  USING (EXISTS (SELECT 1 FROM public.clubs c WHERE c.id = club_id AND c.owner_id = auth.uid()))
  WITH CHECK (EXISTS (SELECT 1 FROM public.clubs c WHERE c.id = club_id AND c.owner_id = auth.uid()));

-- ---------- LINEUP PLAYERS ----------
CREATE TABLE public.lineup_players (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  lineup_id uuid NOT NULL REFERENCES public.lineups(id) ON DELETE CASCADE,
  club_player_id uuid NOT NULL REFERENCES public.club_players(id) ON DELETE CASCADE,
  slot_position public.player_position NOT NULL,
  is_starter boolean NOT NULL,
  slot_index smallint NOT NULL CHECK (slot_index BETWEEN 1 AND 10),
  UNIQUE (lineup_id, slot_index),
  UNIQUE (lineup_id, club_player_id)
);
GRANT SELECT, INSERT, UPDATE, DELETE ON public.lineup_players TO authenticated;
GRANT ALL ON public.lineup_players TO service_role;
ALTER TABLE public.lineup_players ENABLE ROW LEVEL SECURITY;

CREATE POLICY "lineup_players_owner_all" ON public.lineup_players FOR ALL TO authenticated
  USING (EXISTS (
    SELECT 1 FROM public.lineups l JOIN public.clubs c ON c.id = l.club_id
    WHERE l.id = lineup_id AND c.owner_id = auth.uid()
  ))
  WITH CHECK (EXISTS (
    SELECT 1 FROM public.lineups l JOIN public.clubs c ON c.id = l.club_id
    WHERE l.id = lineup_id AND c.owner_id = auth.uid()
  ));

-- ---------- TRAINING SESSIONS ----------
CREATE TABLE public.training_sessions (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  club_id uuid NOT NULL REFERENCES public.clubs(id) ON DELETE CASCADE,
  club_player_id uuid NOT NULL REFERENCES public.club_players(id) ON DELETE CASCADE,
  attribute text NOT NULL CHECK (attribute IN ('velocity','finishing','passing','dribbling','defending','physical','goalkeeping')),
  cost_cents integer NOT NULL CHECK (cost_cents BETWEEN 0 AND 10000),
  day date NOT NULL DEFAULT (now() AT TIME ZONE 'America/Belem')::date,
  progress_delta smallint NOT NULL DEFAULT 1,
  created_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE (club_id, day)
);
CREATE INDEX idx_training_club ON public.training_sessions(club_id, day DESC);
GRANT SELECT ON public.training_sessions TO authenticated;
GRANT ALL ON public.training_sessions TO service_role;
ALTER TABLE public.training_sessions ENABLE ROW LEVEL SECURITY;

CREATE POLICY "training_owner_read" ON public.training_sessions FOR SELECT TO authenticated
  USING (EXISTS (SELECT 1 FROM public.clubs c WHERE c.id = club_id AND c.owner_id = auth.uid())
         OR public.has_role(auth.uid(), 'admin'));

-- ---------- MARKET LISTINGS ----------
CREATE TABLE public.market_listings (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  seller_club_id uuid NOT NULL REFERENCES public.clubs(id) ON DELETE CASCADE,
  club_player_id uuid NOT NULL REFERENCES public.club_players(id) ON DELETE RESTRICT,
  price_cents integer NOT NULL CHECK (price_cents BETWEEN 0 AND 10000),
  status public.market_listing_status NOT NULL DEFAULT 'open',
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  closed_at timestamptz
);
CREATE INDEX idx_market_open ON public.market_listings(status) WHERE status = 'open';
CREATE UNIQUE INDEX idx_market_one_open_per_card ON public.market_listings(club_player_id) WHERE status = 'open';
GRANT SELECT ON public.market_listings TO authenticated;
GRANT ALL ON public.market_listings TO service_role;
ALTER TABLE public.market_listings ENABLE ROW LEVEL SECURITY;
CREATE TRIGGER trg_market_updated_at BEFORE UPDATE ON public.market_listings FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();

CREATE POLICY "market_read_all_authenticated" ON public.market_listings FOR SELECT TO authenticated USING (true);

-- ---------- TRANSFER OFFERS ----------
CREATE TABLE public.transfer_offers (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  from_club_id uuid NOT NULL REFERENCES public.clubs(id) ON DELETE CASCADE,
  to_club_id uuid NOT NULL REFERENCES public.clubs(id) ON DELETE CASCADE,
  cash_cents integer NOT NULL DEFAULT 0 CHECK (cash_cents BETWEEN 0 AND 10000),
  status public.transfer_offer_status NOT NULL DEFAULT 'pending',
  expires_at timestamptz NOT NULL DEFAULT (now() + interval '24 hours'),
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  resolved_at timestamptz,
  CONSTRAINT transfer_distinct_clubs CHECK (from_club_id <> to_club_id)
);
CREATE INDEX idx_offers_to ON public.transfer_offers(to_club_id, status);
CREATE INDEX idx_offers_from ON public.transfer_offers(from_club_id, status);
GRANT SELECT ON public.transfer_offers TO authenticated;
GRANT ALL ON public.transfer_offers TO service_role;
ALTER TABLE public.transfer_offers ENABLE ROW LEVEL SECURITY;
CREATE TRIGGER trg_offers_updated_at BEFORE UPDATE ON public.transfer_offers FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();

CREATE POLICY "offers_participant_read" ON public.transfer_offers FOR SELECT TO authenticated
  USING (
    EXISTS (SELECT 1 FROM public.clubs c WHERE c.id IN (from_club_id, to_club_id) AND c.owner_id = auth.uid())
    OR public.has_role(auth.uid(), 'admin')
  );

CREATE TABLE public.transfer_offer_items (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  offer_id uuid NOT NULL REFERENCES public.transfer_offers(id) ON DELETE CASCADE,
  club_player_id uuid NOT NULL REFERENCES public.club_players(id) ON DELETE RESTRICT,
  side text NOT NULL CHECK (side IN ('from','to')),
  UNIQUE (offer_id, club_player_id)
);
CREATE INDEX idx_offer_items_offer ON public.transfer_offer_items(offer_id);
GRANT SELECT ON public.transfer_offer_items TO authenticated;
GRANT ALL ON public.transfer_offer_items TO service_role;
ALTER TABLE public.transfer_offer_items ENABLE ROW LEVEL SECURITY;

CREATE POLICY "offer_items_participant_read" ON public.transfer_offer_items FOR SELECT TO authenticated
  USING (
    EXISTS (
      SELECT 1 FROM public.transfer_offers o JOIN public.clubs c
        ON c.id IN (o.from_club_id, o.to_club_id)
      WHERE o.id = offer_id AND c.owner_id = auth.uid()
    ) OR public.has_role(auth.uid(), 'admin')
  );

-- ---------- PUSH SUBSCRIPTIONS ----------
CREATE TABLE public.push_subscriptions (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  endpoint text NOT NULL,
  p256dh text NOT NULL,
  auth_key text NOT NULL,
  user_agent text,
  created_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE (user_id, endpoint)
);
CREATE INDEX idx_push_user ON public.push_subscriptions(user_id);
GRANT SELECT, INSERT, DELETE ON public.push_subscriptions TO authenticated;
GRANT ALL ON public.push_subscriptions TO service_role;
ALTER TABLE public.push_subscriptions ENABLE ROW LEVEL SECURITY;

CREATE POLICY "push_owner_read" ON public.push_subscriptions FOR SELECT TO authenticated
  USING (user_id = auth.uid() OR public.has_role(auth.uid(), 'admin'));
CREATE POLICY "push_owner_insert" ON public.push_subscriptions FOR INSERT TO authenticated
  WITH CHECK (user_id = auth.uid());
CREATE POLICY "push_owner_delete" ON public.push_subscriptions FOR DELETE TO authenticated
  USING (user_id = auth.uid());

-- ---------- ADMIN AUDIT LOGS ----------
CREATE TABLE public.admin_audit_logs (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  admin_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE RESTRICT,
  action text NOT NULL,
  target_table text,
  target_id uuid,
  payload jsonb NOT NULL DEFAULT '{}'::jsonb,
  created_at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX idx_audit_admin ON public.admin_audit_logs(admin_id, created_at DESC);
GRANT SELECT ON public.admin_audit_logs TO authenticated;
GRANT ALL ON public.admin_audit_logs TO service_role;
ALTER TABLE public.admin_audit_logs ENABLE ROW LEVEL SECURITY;

CREATE POLICY "audit_admin_read" ON public.admin_audit_logs FOR SELECT TO authenticated
  USING (public.has_role(auth.uid(), 'admin'));
