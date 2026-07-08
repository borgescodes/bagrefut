import { createServerFn } from "@tanstack/react-start";
import { z } from "zod";
import { requireSupabaseAuth } from "@/integrations/supabase/auth-middleware";
import { systemBuyPriceCents, systemSellPriceCents } from "@/domain/calculators/prices";
import { PLAYER_ATTRIBUTE_KEYS } from "@/domain/enums";

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
  .inputValidator((data: unknown) => createClubInput.parse(data))
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
  .inputValidator((data: unknown) => updateClubIdentityInput.parse(data))
  .handler(async ({ data, context }) => {
    const { data: club, error } = await context.supabase.rpc("update_club_identity", {
      _club_id: data.clubId,
      _name: data.name ?? null,
      _abbreviation: data.abbreviation ?? null,
      _badge_code: data.badgeCode ?? null,
    });
    if (error) throw new Error(error.message);
    return { club: club?.[0] ?? null };
  });

export const openInitialPack = createServerFn({ method: "POST" })
  .middleware([requireSupabaseAuth])
  .inputValidator((data: unknown) => z.object({ clubId: z.string().uuid() }).parse(data))
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
  .inputValidator((data: unknown) => clubPlayerInput.parse(data))
  .handler(async ({ data, context }) => {
    const { data: result, error } = await context.supabase.rpc("buy_player_from_system", {
      _club_player_id: data.clubPlayerId,
    });
    if (error) throw new Error(error.message);
    return { result: result?.[0] ?? null };
  });

export const sellPlayerToSystem = createServerFn({ method: "POST" })
  .middleware([requireSupabaseAuth])
  .inputValidator((data: unknown) => clubPlayerInput.parse(data))
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
  .inputValidator((data: unknown) => trainClubPlayerInput.parse(data))
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
