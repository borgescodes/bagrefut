import { createServerFn } from "@tanstack/react-start";
import { z } from "zod";
import { requireSupabaseAuth } from "@/integrations/supabase/auth-middleware";
import { validatePassword, validatePasswordConfirmation } from "@/domain/rules/validators";

const changeTemporaryPasswordInput = z.object({
  newPassword: z.string(),
  confirmation: z.string(),
});

function mustChangePasswordMetadata(
  appMetadata: Record<string, unknown>,
  mustChangePassword: boolean,
) {
  return {
    ...appMetadata,
    must_change_password: mustChangePassword,
  };
}

export const changeTemporaryPassword = createServerFn({ method: "POST" })
  .middleware([requireSupabaseAuth])
  .validator((data: unknown) => changeTemporaryPasswordInput.parse(data))
  .handler(async ({ data, context }) => {
    const password = validatePassword(data.newPassword);
    if (!password.ok) throw new Error(password.error);

    const confirmation = validatePasswordConfirmation(data.newPassword, data.confirmation);
    if (!confirmation.ok) throw new Error("password_confirmation_mismatch");

    const { supabaseAdmin } = await import("@/integrations/supabase/client.server");
    const { data: currentUser, error: getUserError } = await supabaseAdmin.auth.admin.getUserById(
      context.userId,
    );
    if (getUserError || !currentUser?.user) throw new Error("password_update_failed");

    const appMetadata = (currentUser.user.app_metadata ?? {}) as Record<string, unknown>;
    if (appMetadata.must_change_password !== true) {
      throw new Error("temporary_password_change_not_required");
    }

    const { data: updatedUser, error: updateError } = await supabaseAdmin.auth.admin.updateUserById(
      context.userId,
      {
        password: data.newPassword,
        app_metadata: mustChangePasswordMetadata(appMetadata, false),
      },
    );
    if (updateError) throw new Error("password_update_failed");
    if (!updatedUser?.user?.id) throw new Error("password_update_failed");

    return { ok: true };
  });
