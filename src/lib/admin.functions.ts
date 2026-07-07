import { createServerFn } from "@tanstack/react-start";
import type { SupabaseClient } from "@supabase/supabase-js";
import { z } from "zod";
import { requireSupabaseAuth } from "@/integrations/supabase/auth-middleware";
import type { Database } from "@/integrations/supabase/types";

async function assertApprovedAdmin(ctx: { supabase: SupabaseClient<Database>; userId: string }) {
  const [approvedRes, roleRes] = await Promise.all([
    ctx.supabase.rpc("is_approved_user", { _user_id: ctx.userId }),
    ctx.supabase.rpc("has_role", {
      _user_id: ctx.userId,
      _role: "admin",
    }),
  ]);
  if (approvedRes.error) throw new Error(approvedRes.error.message);
  if (roleRes.error) throw new Error(roleRes.error.message);
  if (!approvedRes.data) throw new Error("profile_not_approved");
  if (!roleRes.data) throw new Error("forbidden_not_admin");
}

export const adminListPendingUsers = createServerFn({ method: "GET" })
  .middleware([requireSupabaseAuth])
  .handler(async ({ context }) => {
    await assertApprovedAdmin(context);
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
      reason: z.string().trim().max(500).optional(),
    }).parse(data),
  )
  .handler(async ({ data, context }) => {
    const { data: result, error } = await context.supabase.rpc("admin_set_user_status", {
      _target_user_id: data.userId,
      _new_status: data.status,
      _reason: data.reason ?? null,
    });
    if (error) throw new Error(error.message);

    const row = Array.isArray(result) ? result[0] : result;
    if (!row) throw new Error("admin_set_user_status_empty_result");
    return row;
  });

/**
 * Generates a temporary password for a user (admin action).
 * Service-role only path — the temporary secret is returned to the admin caller once.
 */
export const adminResetUserPassword = createServerFn({ method: "POST" })
  .middleware([requireSupabaseAuth])
  .inputValidator((data: unknown) => z.object({ userId: z.string().uuid() }).parse(data))
  .handler(async ({ data, context }) => {
    await assertApprovedAdmin(context);
    const { supabaseAdmin } = await import("@/integrations/supabase/client.server");
    // Generate a random 12-char password with letters+digits.
    const alphabet = "ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnpqrstuvwxyz23456789";
    const bytes = new Uint8Array(12);
    crypto.getRandomValues(bytes);
    let tempPassword = "";
    for (const b of bytes) tempPassword += alphabet[b % alphabet.length];
    // Ensure it satisfies our client-side password rule (letter + digit).
    tempPassword = tempPassword.replace(/^(.)/, "A").replace(/(.)$/, "1");

    const { data: updatedUser, error } = await supabaseAdmin.auth.admin.updateUserById(data.userId, {
      password: tempPassword,
    });
    if (error) throw new Error(error.message);
    if (!updatedUser?.user?.id) throw new Error("password_update_missing_user");

    const { error: auditError } = await supabaseAdmin.from("admin_audit_logs").insert({
      admin_id: context.userId,
      action: "reset_user_password",
      target_table: "auth.users",
      target_id: data.userId,
      payload: {
        result: "password_updated",
        auth_user_id: updatedUser.user.id,
        audit_atomic: false,
      },
    });
    if (auditError) throw new Error(`password_updated_but_audit_failed: ${auditError.message}`);

    return { tempPassword };
  });
