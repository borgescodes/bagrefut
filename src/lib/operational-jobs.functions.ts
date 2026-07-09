import { createServerFn } from "@tanstack/react-start";
import type { SupabaseClient } from "@supabase/supabase-js";
import { z } from "zod";
import { requireSupabaseAuth } from "@/integrations/supabase/auth-middleware";
import type { Database, Json } from "@/integrations/supabase/types";
import { assertApprovedAdmin } from "@/lib/admin.functions";
import { retryOperationalJobRun } from "@/lib/internal-jobs";

export type OperationalJobRunStatus = "pending" | "running" | "succeeded" | "failed" | "dead";

export interface OperationalJobRun {
  id: string;
  job_type: "round_lock" | "round_simulation" | "round_finalize" | "season_finalize";
  target_id: string;
  scheduled_for: string;
  status: OperationalJobRunStatus;
  attempt_count: number;
  max_attempts: number;
  next_retry_at: string | null;
  started_at: string | null;
  finished_at: string | null;
  last_error: string | null;
  result: Json | null;
  created_at: string;
  updated_at: string;
}

type JsonRpcResponse = {
  data: unknown;
  error: { message: string } | null;
};

const retryInput = z.object({
  jobRunId: z.string().uuid(),
});

function rpcClient(client: SupabaseClient<Database>) {
  return client.rpc as unknown as (
    fn: string,
    args?: Record<string, unknown>,
  ) => Promise<JsonRpcResponse>;
}

function readRecord(value: unknown): Record<string, unknown> {
  if (!value || typeof value !== "object" || Array.isArray(value)) return {};
  return value as Record<string, unknown>;
}

function readString(value: unknown): string {
  return typeof value === "string" ? value : "";
}

function readNullableString(value: unknown): string | null {
  return typeof value === "string" ? value : null;
}

function readNumber(value: unknown): number {
  return typeof value === "number" ? value : 0;
}

function readStatus(value: unknown): OperationalJobRunStatus {
  if (
    value === "pending" ||
    value === "running" ||
    value === "succeeded" ||
    value === "failed" ||
    value === "dead"
  ) {
    return value;
  }
  return "pending";
}

function parseOperationalJobRun(value: unknown): OperationalJobRun {
  const row = readRecord(value);
  return {
    id: readString(row.id),
    job_type: readString(row.job_type) as OperationalJobRun["job_type"],
    target_id: readString(row.target_id),
    scheduled_for: readString(row.scheduled_for),
    status: readStatus(row.status),
    attempt_count: readNumber(row.attempt_count),
    max_attempts: readNumber(row.max_attempts),
    next_retry_at: readNullableString(row.next_retry_at),
    started_at: readNullableString(row.started_at),
    finished_at: readNullableString(row.finished_at),
    last_error: readNullableString(row.last_error),
    result: (row.result ?? null) as Json | null,
    created_at: readString(row.created_at),
    updated_at: readString(row.updated_at),
  };
}

export const adminListOperationalJobRuns = createServerFn({ method: "GET" })
  .middleware([requireSupabaseAuth])
  .handler(async ({ context }) => {
    await assertApprovedAdmin(context);

    const { data, error } = await rpcClient(context.supabase)("admin_list_operational_job_runs", {
      _limit: 50,
      _status: null,
    });
    if (error) throw new Error(error.message);

    return {
      jobs: Array.isArray(data) ? data.map(parseOperationalJobRun) : [],
    };
  });

export const adminRetryOperationalJobRun = createServerFn({ method: "POST" })
  .middleware([requireSupabaseAuth])
  .validator((data: unknown) => retryInput.parse(data))
  .handler(async ({ data, context }) => {
    await assertApprovedAdmin(context);
    const { supabaseAdmin } = await import("@/integrations/supabase/client.server");
    const result = await retryOperationalJobRun(
      supabaseAdmin as unknown as Parameters<typeof retryOperationalJobRun>[0],
      data.jobRunId,
    );
    return { result: result as Json };
  });
