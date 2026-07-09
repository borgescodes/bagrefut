import { createServerFn } from "@tanstack/react-start";
import type { SupabaseClient } from "@supabase/supabase-js";
import { z } from "zod";
import { requireSupabaseAuth } from "@/integrations/supabase/auth-middleware";
import { systemBuyPriceCents, systemSellPriceCents } from "@/domain/calculators/prices";
import { PLAYER_ATTRIBUTE_KEYS } from "@/domain/enums";
import type {
  JsonValue,
  MatchDetails,
  MatchEvent,
  MatchFinalResult,
  MatchScoreSummary,
} from "@/domain/types";
import type { Database } from "@/integrations/supabase/types";
import { canRequestMatchEvents } from "@/lib/match-access";

/**
 * Returns the current user's profile (id, username, status) and roles.
 * Uses requireSupabaseAuth so RLS applies. Nothing sensitive is exposed.
 */
export const getMe = createServerFn({ method: "GET" })
  .middleware([requireSupabaseAuth])
  .handler(async ({ context }) => {
    const { supabase, userId } = context;
    const [profileRes, rolesRes] = await Promise.all([
      supabase
        .from("profiles")
        .select("id, username, status, created_at")
        .eq("id", userId)
        .maybeSingle(),
      supabase.from("user_roles").select("role").eq("user_id", userId),
    ]);
    if (profileRes.error) throw new Error(profileRes.error.message);
    if (rolesRes.error) throw new Error(rolesRes.error.message);
    return {
      profile: profileRes.data,
      roles: (rolesRes.data ?? []).map((r) => r.role as "admin" | "user"),
    };
  });

/** Public listing of active club badges (name + asset_path). */
export const listBadges = createServerFn({ method: "GET" })
  .middleware([requireSupabaseAuth])
  .handler(async ({ context }) => {
    const { data, error } = await context.supabase
      .from("club_badges")
      .select("id, code, label, asset_path, sort_order")
      .eq("is_active", true)
      .order("sort_order");
    if (error) throw new Error(error.message);
    return data ?? [];
  });

const createClubInput = z.object({
  name: z.string().min(1),
  abbreviation: z.string().min(1),
  badgeCode: z.string().min(1),
});

export const createClub = createServerFn({ method: "POST" })
  .middleware([requireSupabaseAuth])
  .validator((data: unknown) => createClubInput.parse(data))
  .handler(async ({ data, context }) => {
    const { data: clubId, error } = await context.supabase.rpc("create_club", {
      _name: data.name,
      _abbreviation: data.abbreviation,
      _badge_code: data.badgeCode,
    });
    if (error) throw new Error(error.message);
    return { clubId: clubId as string };
  });

const updateClubIdentityInput = z.object({
  clubId: z.string().uuid(),
  name: z.string().nullable().optional(),
  abbreviation: z.string().nullable().optional(),
  badgeCode: z.string().nullable().optional(),
});

export const updateClubIdentity = createServerFn({ method: "POST" })
  .middleware([requireSupabaseAuth])
  .validator((data: unknown) => updateClubIdentityInput.parse(data))
  .handler(async ({ data, context }) => {
    const { data: club, error } = await context.supabase.rpc("update_club_identity", {
      _club_id: data.clubId,
      _name: data.name ?? undefined,
      _abbreviation: data.abbreviation ?? undefined,
      _badge_code: data.badgeCode ?? undefined,
    });
    if (error) throw new Error(error.message);
    return { club: club?.[0] ?? null };
  });

export const openInitialPack = createServerFn({ method: "POST" })
  .middleware([requireSupabaseAuth])
  .validator((data: unknown) => z.object({ clubId: z.string().uuid() }).parse(data))
  .handler(async ({ data, context }) => {
    const { data: items, error } = await context.supabase.rpc("open_initial_pack", {
      _club_id: data.clubId,
    });
    if (error) throw new Error(error.message);
    return { items: items ?? [] };
  });

export const getMyRoster = createServerFn({ method: "GET" })
  .middleware([requireSupabaseAuth])
  .handler(async ({ context }) => {
    const { data, error } = await context.supabase
      .from("club_players")
      .select(
        `
        id,
        club_id,
        player_id,
        acquired_at,
        is_reserved,
        players (
          id,
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
        ),
        club_player_attribute_progress (
          attribute,
          progress,
          updated_at
        )
      `,
      )
      .order("acquired_at", { ascending: true });

    if (error) throw new Error(error.message);
    return data ?? [];
  });

export const listSystemMarketStock = createServerFn({ method: "GET" })
  .middleware([requireSupabaseAuth])
  .handler(async ({ context }) => {
    const { data, error } = await context.supabase
      .from("system_market_stock")
      .select(
        `
        club_player_id,
        acquired_from_club_id,
        acquired_price_cents,
        acquired_at,
        club_players (
          id,
          club_id,
          player_id,
          acquired_at,
          is_reserved,
          players (
            id,
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
        )
      `,
      )
      .order("acquired_at", { ascending: true });

    if (error) throw new Error(error.message);
    return (data ?? []).map((stock) => {
      const player = stock.club_players?.players;
      const reference = player?.reference_value_cents ?? 0;
      return {
        ...stock,
        buyPriceCents: systemSellPriceCents(reference),
        sellPriceCents: systemBuyPriceCents(reference),
      };
    });
  });

const clubPlayerInput = z.object({ clubPlayerId: z.string().uuid() });

export const buyPlayerFromSystem = createServerFn({ method: "POST" })
  .middleware([requireSupabaseAuth])
  .validator((data: unknown) => clubPlayerInput.parse(data))
  .handler(async ({ data, context }) => {
    const { data: result, error } = await context.supabase.rpc("buy_player_from_system", {
      _club_player_id: data.clubPlayerId,
    });
    if (error) throw new Error(error.message);
    return { result: result?.[0] ?? null };
  });

export const sellPlayerToSystem = createServerFn({ method: "POST" })
  .middleware([requireSupabaseAuth])
  .validator((data: unknown) => clubPlayerInput.parse(data))
  .handler(async ({ data, context }) => {
    const { data: result, error } = await context.supabase.rpc("sell_player_to_system", {
      _club_player_id: data.clubPlayerId,
    });
    if (error) throw new Error(error.message);
    return { result: result?.[0] ?? null };
  });

const trainClubPlayerInput = clubPlayerInput.extend({
  attribute: z.enum(PLAYER_ATTRIBUTE_KEYS),
});

export const trainClubPlayer = createServerFn({ method: "POST" })
  .middleware([requireSupabaseAuth])
  .validator((data: unknown) => trainClubPlayerInput.parse(data))
  .handler(async ({ data, context }) => {
    const { data: result, error } = await context.supabase.rpc("train_club_player", {
      _club_player_id: data.clubPlayerId,
      _attribute: data.attribute,
    });
    if (error) throw new Error(error.message);
    return { result: result?.[0] ?? null };
  });

/** Returns the caller's club (if any). */
export const getMyClub = createServerFn({ method: "GET" })
  .middleware([requireSupabaseAuth])
  .handler(async ({ context }) => {
    const { data, error } = await context.supabase
      .from("clubs")
      .select("id, name, abbreviation, badge_id, balance_cents, created_at")
      .eq("owner_id", context.userId)
      .maybeSingle();
    if (error) throw new Error(error.message);
    return data;
  });

const matchIdInput = z.object({ matchId: z.string().uuid() });
const roundIdInput = z.object({ roundId: z.string().uuid() });

type JsonRpcResponse = {
  data: JsonValue | null;
  error: { message: string } | null;
};

async function callJsonRpc(
  supabase: SupabaseClient<Database>,
  functionName: string,
  args?: Record<string, unknown>,
): Promise<JsonValue> {
  const rpc = supabase.rpc as unknown as (
    fn: string,
    args?: Record<string, unknown>,
  ) => Promise<JsonRpcResponse>;
  const { data, error } = await rpc(functionName, args);
  if (error) throw new Error(error.message);
  return data;
}

function asMatchSummary(row: Record<string, unknown>): MatchScoreSummary {
  return {
    match_id: String(row.match_id),
    status: row.status as MatchScoreSummary["status"],
    round_number: Number(row.round_number),
    competition_name: String(row.competition_name),
    starts_at: String(row.starts_at),
    home_club_id: String(row.home_club_id),
    home_club_name: String(row.home_club_name),
    home_club_abbreviation: String(row.home_club_abbreviation),
    home_club_badge_path: row.home_club_badge_path ? String(row.home_club_badge_path) : null,
    away_club_id: String(row.away_club_id),
    away_club_name: String(row.away_club_name),
    away_club_abbreviation: String(row.away_club_abbreviation),
    away_club_badge_path: row.away_club_badge_path ? String(row.away_club_badge_path) : null,
    home_goals: Number(row.home_goals),
    away_goals: Number(row.away_goals),
    final_result: String(row.final_result) as MatchFinalResult,
  };
}

async function loadCallerMatchContext(
  context: {
    supabase: SupabaseClient<Database>;
    userId: string;
  },
  matchId?: string,
) {
  const [summariesRes, clubRes, rolesRes] = await Promise.all([
    context.supabase.rpc("list_match_score_summaries", { _match_id: matchId ?? undefined }),
    context.supabase.from("clubs").select("id").eq("owner_id", context.userId).maybeSingle(),
    context.supabase.from("user_roles").select("role").eq("user_id", context.userId),
  ]);

  if (summariesRes.error) throw new Error(summariesRes.error.message);
  if (clubRes.error) throw new Error(clubRes.error.message);
  if (rolesRes.error) throw new Error(rolesRes.error.message);

  return {
    summaries: (summariesRes.data ?? []).map((row) =>
      asMatchSummary(row as Record<string, unknown>),
    ),
    myClubId: clubRes.data?.id ?? null,
    isAdmin: (rolesRes.data ?? []).some((role) => role.role === "admin"),
  };
}

export const listMatchSummaries = createServerFn({ method: "GET" })
  .middleware([requireSupabaseAuth])
  .handler(async ({ context }) => {
    const { summaries } = await loadCallerMatchContext(context);
    return { matches: summaries };
  });

export const getMatchDetails = createServerFn({ method: "GET" })
  .middleware([requireSupabaseAuth])
  .validator((data: unknown) => matchIdInput.parse(data))
  .handler(async ({ data, context }) => {
    const { summaries, myClubId, isAdmin } = await loadCallerMatchContext(context, data.matchId);
    const summary = summaries[0];
    if (!summary) throw new Error("match_not_found");

    const details: MatchDetails = {
      ...summary,
      can_view_events: canRequestMatchEvents({ summary, myClubId, isAdmin }),
    };
    return { match: details };
  });

export const getMatchEvents = createServerFn({ method: "GET" })
  .middleware([requireSupabaseAuth])
  .validator((data: unknown) => matchIdInput.parse(data))
  .handler(async ({ data, context }) => {
    const { summaries, myClubId, isAdmin } = await loadCallerMatchContext(context, data.matchId);
    const summary = summaries[0];
    if (!summary) throw new Error("match_not_found");

    if (!canRequestMatchEvents({ summary, myClubId, isAdmin })) {
      throw new Error("match_events_forbidden");
    }

    const { data: events, error } = await context.supabase
      .from("match_events")
      .select("id, match_id, minute, reveal_at, event_type, club_id, player_id, meta")
      .eq("match_id", data.matchId)
      .order("minute", { ascending: true })
      .order("created_at", { ascending: true });

    if (error) throw new Error(error.message);
    return { events: (events ?? []) as MatchEvent[] };
  });

export const getCurrentRoundState = createServerFn({ method: "GET" })
  .middleware([requireSupabaseAuth])
  .handler(async ({ context }) => {
    const state = await callJsonRpc(context.supabase, "get_current_round_state");
    return { state };
  });

export const getMatchPublicDetails = createServerFn({ method: "GET" })
  .middleware([requireSupabaseAuth])
  .validator((data: unknown) => matchIdInput.parse(data))
  .handler(async ({ data, context }) => {
    const details = await callJsonRpc(context.supabase, "get_match_public_details", {
      _match_id: data.matchId,
    });
    return { details };
  });

export const simulateMatchAdmin = createServerFn({ method: "POST" })
  .middleware([requireSupabaseAuth])
  .validator((data: unknown) => matchIdInput.parse(data))
  .handler(async ({ data, context }) => {
    const result = await callJsonRpc(context.supabase, "simulate_match", {
      _match_id: data.matchId,
    });
    return { result };
  });

export const simulateRoundAdmin = createServerFn({ method: "POST" })
  .middleware([requireSupabaseAuth])
  .validator((data: unknown) => roundIdInput.parse(data))
  .handler(async ({ data, context }) => {
    const result = await callJsonRpc(context.supabase, "simulate_round", {
      _round_id: data.roundId,
    });
    return { result };
  });
