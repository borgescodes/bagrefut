import { createServerFn } from "@tanstack/react-start";
import { z } from "zod";
import { requireSupabaseAuth } from "@/integrations/supabase/auth-middleware";

async function assertAdmin(ctx: { supabase: any; userId: string }) {
  const { data, error } = await ctx.supabase.rpc("has_role", {
    _user_id: ctx.userId,
    _role: "admin",
  });
  if (error) throw new Error(error.message);
  if (!data) throw new Error("forbidden_not_admin");
}

export const adminListPendingUsers = createServerFn({ method: "GET" })
  .middleware([requireSupabaseAuth])
  .handler(async ({ context }) => {
    await assertAdmin(context);
    const { supabaseAdmin } = await import("@/integrations/supabase/client.server");
    const { data, error } = await supabaseAdmin
      .from("profiles")
      .select("id, username, status, created_at")
      .in("status", ["pending", "approved", "blocked"])
      .order("created_at", { ascending: false })
      .limit(200);
    if (error) throw new Error(error.message);
    return data ?? [];
  });

export const adminSetUserStatus = createServerFn({ method: "POST" })
  .middleware([requireSupabaseAuth])
  .inputValidator((data: unknown) =>
    z.object({
      userId: z.string().uuid(),
      status: z.enum(["pending", "approved", "blocked"]),
    }).parse(data),
  )
  .handler(async ({ data, context }) => {
    await assertAdmin(context);
    const { supabaseAdmin } = await import("@/integrations/supabase/client.server");
    const { error } = await supabaseAdmin
      .from("profiles")
      .update({ status: data.status })
      .eq("id", data.userId);
    if (error) throw new Error(error.message);
    await supabaseAdmin.from("admin_audit_logs").insert({
      admin_id: context.userId,
      action: "set_user_status",
      target_table: "profiles",
      target_id: data.userId,
      payload: { status: data.status },
    });
    return { ok: true };
  });

/**
 * Generates a temporary password for a user (admin action).
 * Service-role only path — the temporary secret is returned to the admin caller once.
 */
export const adminResetUserPassword = createServerFn({ method: "POST" })
  .middleware([requireSupabaseAuth])
  .inputValidator((data: unknown) => z.object({ userId: z.string().uuid() }).parse(data))
  .handler(async ({ data, context }) => {
    await assertAdmin(context);
    const { supabaseAdmin } = await import("@/integrations/supabase/client.server");
    // Generate a random 12-char password with letters+digits.
    const alphabet = "ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnpqrstuvwxyz23456789";
    const bytes = new Uint8Array(12);
    crypto.getRandomValues(bytes);
    let tempPassword = "";
    for (const b of bytes) tempPassword += alphabet[b % alphabet.length];
    // Ensure it satisfies our client-side password rule (letter + digit).
    tempPassword = tempPassword.replace(/^(.)/, "A").replace(/(.)$/, "1");

    const { error } = await supabaseAdmin.auth.admin.updateUserById(data.userId, {
      password: tempPassword,
    });
    if (error) throw new Error(error.message);

    await supabaseAdmin.from("admin_audit_logs").insert({
      admin_id: context.userId,
      action: "reset_user_password",
      target_table: "auth.users",
      target_id: data.userId,
      payload: {},
    });
    return { tempPassword };
  });
