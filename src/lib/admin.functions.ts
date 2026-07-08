import { createServerFn } from "@tanstack/react-start";
import type { SupabaseClient } from "@supabase/supabase-js";
import { z } from "zod";
import { requireSupabaseAuth } from "@/integrations/supabase/auth-middleware";
import type { Database } from "@/integrations/supabase/types";
import { validatePassword } from "@/domain/rules/validators";

export const TEMPORARY_PASSWORD_MIN_LENGTH = 12;

const TEMPORARY_PASSWORD_UPPERCASE = "ABCDEFGHJKLMNPQRSTUVWXYZ";
const TEMPORARY_PASSWORD_LOWERCASE = "abcdefghijkmnopqrstuvwxyz";
const TEMPORARY_PASSWORD_NUMBERS = "23456789";
const TEMPORARY_PASSWORD_ALPHABET =
  TEMPORARY_PASSWORD_UPPERCASE + TEMPORARY_PASSWORD_LOWERCASE + TEMPORARY_PASSWORD_NUMBERS;

function secureRandomIndex(length: number): number {
  if (length <= 0) throw new Error("invalid_random_range");
  const cryptoApi = globalThis.crypto;
  if (!cryptoApi?.getRandomValues) throw new Error("secure_random_unavailable");

  const max = 0xffffffff;
  const limit = max - (max % length);
  const bytes = new Uint32Array(1);
  do {
    cryptoApi.getRandomValues(bytes);
  } while (bytes[0] >= limit);
  return bytes[0] % length;
}

function pickSecureChar(alphabet: string): string {
  return alphabet[secureRandomIndex(alphabet.length)];
}

function shuffleSecure(chars: string[]): string[] {
  const shuffled = [...chars];
  for (let index = shuffled.length - 1; index > 0; index -= 1) {
    const swapIndex = secureRandomIndex(index + 1);
    [shuffled[index], shuffled[swapIndex]] = [shuffled[swapIndex], shuffled[index]];
  }
  return shuffled;
}

export function generateTemporaryPassword(length = TEMPORARY_PASSWORD_MIN_LENGTH): string {
  const safeLength = Math.max(length, TEMPORARY_PASSWORD_MIN_LENGTH);
  for (let attempt = 0; attempt < 10; attempt += 1) {
    const chars = [
      pickSecureChar(TEMPORARY_PASSWORD_UPPERCASE),
      pickSecureChar(TEMPORARY_PASSWORD_LOWERCASE),
      pickSecureChar(TEMPORARY_PASSWORD_NUMBERS),
    ];
    while (chars.length < safeLength) chars.push(pickSecureChar(TEMPORARY_PASSWORD_ALPHABET));
    const password = shuffleSecure(chars).join("");
    if (validatePassword(password).ok) return password;
  }
  throw new Error("temporary_password_generation_failed");
}

export function buildPasswordResetAppMetadata(
  appMetadata: Record<string, unknown> | null | undefined,
) {
  return {
    ...(appMetadata ?? {}),
    must_change_password: true,
  };
}

export function buildPasswordResetAuditPayload() {
  return {
    result: "temporary_password_created",
    must_change_password: true,
  };
}

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
  .validator((data: unknown) =>
    z
      .object({
        userId: z.string().uuid(),
        status: z.enum(["pending", "approved", "blocked"]),
        reason: z.string().trim().max(500).optional(),
      })
      .parse(data),
  )
  .handler(async ({ data, context }) => {
    const { data: result, error } = await context.supabase.rpc("admin_set_user_status", {
      _target_user_id: data.userId,
      _new_status: data.status,
      _reason: data.reason ?? undefined,
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
  .validator((data: unknown) => z.object({ userId: z.string().uuid() }).parse(data))
  .handler(async ({ data, context }) => {
    await assertApprovedAdmin(context);
    const { supabaseAdmin } = await import("@/integrations/supabase/client.server");

    const { data: targetProfile, error: profileError } = await supabaseAdmin
      .from("profiles")
      .select("id, username")
      .eq("id", data.userId)
      .maybeSingle();
    if (profileError) throw new Error(profileError.message);
    if (!targetProfile) throw new Error("target_profile_not_found");

    const { data: targetAuthUser, error: targetAuthError } =
      await supabaseAdmin.auth.admin.getUserById(data.userId);
    if (targetAuthError || !targetAuthUser?.user) throw new Error("target_auth_user_not_found");

    const tempPassword = generateTemporaryPassword();
    const appMetadata = buildPasswordResetAppMetadata(
      (targetAuthUser.user.app_metadata ?? {}) as Record<string, unknown>,
    );

    const { data: updatedUser, error } = await supabaseAdmin.auth.admin.updateUserById(
      data.userId,
      {
        password: tempPassword,
        app_metadata: appMetadata,
      },
    );
    if (error) throw new Error("password_update_failed");
    if (!updatedUser?.user?.id) throw new Error("password_update_missing_user");

    const { error: auditError } = await supabaseAdmin.from("admin_audit_logs").insert({
      admin_id: context.userId,
      action: "reset_user_password",
      target_table: "auth.users",
      target_id: data.userId,
      payload: buildPasswordResetAuditPayload(),
    });
    if (auditError) throw new Error(`password_updated_but_audit_failed: ${auditError.message}`);

    return { tempPassword, username: targetProfile.username };
  });
