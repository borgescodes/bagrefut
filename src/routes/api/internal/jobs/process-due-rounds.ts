import { createFileRoute } from "@tanstack/react-router";
import { handleInternalProcessDueRounds, type ProcessJobClient } from "@/lib/internal-jobs";

export const Route = createFileRoute("/api/internal/jobs/process-due-rounds")({
  server: {
    handlers: {
      POST: async ({ request }) => {
        const { supabaseAdmin } = await import("@/integrations/supabase/client.server");
        return handleInternalProcessDueRounds(request, {
          getInternalJobSecret: () => process.env.INTERNAL_JOB_SECRET,
          getSupabaseAdmin: () => supabaseAdmin as unknown as ProcessJobClient,
          allowNowOverride:
            process.env.NODE_ENV !== "production" ||
            process.env.INTERNAL_JOBS_ALLOW_NOW_OVERRIDE === "true",
        });
      },
    },
  },
});
