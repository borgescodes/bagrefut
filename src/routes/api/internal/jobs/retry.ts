import { createFileRoute } from "@tanstack/react-router";
import { handleInternalRetryJob, type RetryJobClient } from "@/lib/internal-jobs";

export const Route = createFileRoute("/api/internal/jobs/retry")({
  server: {
    handlers: {
      POST: async ({ request }) => {
        const { supabaseAdmin } = await import("@/integrations/supabase/client.server");
        return handleInternalRetryJob(request, {
          getInternalJobSecret: () => process.env.INTERNAL_JOB_SECRET,
          getSupabaseAdmin: () => supabaseAdmin as unknown as RetryJobClient,
        });
      },
    },
  },
});
