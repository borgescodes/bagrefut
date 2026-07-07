import { createServerFn } from "@tanstack/react-start";
import { z } from "zod";
import { requireSupabaseAuth } from "@/integrations/supabase/auth-middleware";

/**
 * Returns the current user's profile (id, username, status) and roles.
 * Uses requireSupabaseAuth so RLS applies. Nothing sensitive is exposed.
 */
export const getMe = createServerFn({ method: "GET" })
  .middleware([requireSupabaseAuth])
  .handler(async ({ context }) => {
    const { supabase, userId } = context;
    const [profileRes, rolesRes] = await Promise.all([
      supabase.from("profiles").select("id, username, status, created_at").eq("id", userId).maybeSingle(),
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
  name: z.string().min(3).max(24),
  abbreviation: z.string().min(2).max(4),
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
