import { describe, expect, it, vi } from "vitest";
import {
  handleInternalProcessDueRounds,
  handleInternalRetryJob,
  sanitizeOperationalError,
} from "@/lib/internal-jobs";

const SECRET = "internal-secret-123";

function processRequest(secret?: string, body?: unknown) {
  return new Request("https://bagrefut.test/api/internal/jobs/process-due-rounds", {
    method: "POST",
    headers: {
      ...(secret ? { Authorization: `Bearer ${secret}` } : {}),
      "Content-Type": "application/json",
    },
    body: body === undefined ? undefined : JSON.stringify(body),
  });
}

function retryRequest(secret?: string, body?: unknown) {
  return new Request("https://bagrefut.test/api/internal/jobs/retry", {
    method: "POST",
    headers: {
      ...(secret ? { Authorization: `Bearer ${secret}` } : {}),
      "Content-Type": "application/json",
    },
    body: body === undefined ? undefined : JSON.stringify(body),
  });
}

describe("internal job route handlers", () => {
  it("returns 401 when the internal secret is missing", async () => {
    const supabase = { rpc: vi.fn() };

    const response = await handleInternalProcessDueRounds(processRequest(), {
      getInternalJobSecret: () => SECRET,
      getSupabaseAdmin: () => supabase,
      allowNowOverride: false,
    });

    expect(response.status).toBe(401);
    expect(await response.json()).toEqual({ error: "unauthorized" });
    expect(supabase.rpc).not.toHaveBeenCalled();
  });

  it("returns 401 when the internal secret is invalid", async () => {
    const supabase = { rpc: vi.fn() };

    const response = await handleInternalProcessDueRounds(processRequest("wrong"), {
      getInternalJobSecret: () => SECRET,
      getSupabaseAdmin: () => supabase,
      allowNowOverride: false,
    });

    expect(response.status).toBe(401);
    expect(await response.json()).toEqual({ error: "unauthorized" });
    expect(supabase.rpc).not.toHaveBeenCalled();
  });

  it("calls process_due_rounds with a valid internal secret", async () => {
    const result = {
      locked: 1,
      simulated: 1,
      finalized: 0,
      seasons_finished: 0,
      failed: 0,
      dead: 0,
    };
    const supabase = {
      rpc: vi.fn().mockResolvedValue({ data: result, error: null }),
    };

    const response = await handleInternalProcessDueRounds(processRequest(SECRET), {
      getInternalJobSecret: () => SECRET,
      getSupabaseAdmin: () => supabase,
      allowNowOverride: false,
    });

    expect(response.status).toBe(200);
    expect(await response.json()).toEqual({ result });
    expect(supabase.rpc).toHaveBeenCalledWith("process_due_rounds", {});
  });

  it("accepts _now only when explicit development override is enabled", async () => {
    const supabase = {
      rpc: vi.fn().mockResolvedValue({
        data: { locked: 0, simulated: 0, finalized: 0, seasons_finished: 0, failed: 0, dead: 0 },
        error: null,
      }),
    };

    const response = await handleInternalProcessDueRounds(
      processRequest(SECRET, { _now: "2026-07-09T22:07:00-03:00" }),
      {
        getInternalJobSecret: () => SECRET,
        getSupabaseAdmin: () => supabase,
        allowNowOverride: true,
      },
    );

    expect(response.status).toBe(200);
    expect(supabase.rpc).toHaveBeenCalledWith("process_due_rounds", {
      _now: "2026-07-09T22:07:00-03:00",
    });
  });

  it("rejects invalid retry payloads before touching Supabase", async () => {
    const supabase = { rpc: vi.fn() };

    const response = await handleInternalRetryJob(retryRequest(SECRET, { job_run_id: "bad-id" }), {
      getInternalJobSecret: () => SECRET,
      getSupabaseAdmin: () => supabase,
    });

    expect(response.status).toBe(400);
    expect(await response.json()).toEqual({ error: "invalid_payload" });
    expect(supabase.rpc).not.toHaveBeenCalled();
  });

  it("requeues failed jobs through the internal retry RPC", async () => {
    const result = {
      id: "00000000-0000-0000-0000-000000000123",
      status: "pending",
      manual_retry_count: 1,
    };
    const supabase = {
      rpc: vi.fn().mockResolvedValue({ data: result, error: null }),
    };

    const response = await handleInternalRetryJob(
      retryRequest(SECRET, { job_run_id: "00000000-0000-0000-0000-000000000123" }),
      {
        getInternalJobSecret: () => SECRET,
        getSupabaseAdmin: () => supabase,
      },
    );

    expect(response.status).toBe(200);
    expect(await response.json()).toEqual({ result });
    expect(supabase.rpc).toHaveBeenCalledWith("_operational_retry_job_run", {
      _job_run_id: "00000000-0000-0000-0000-000000000123",
    });
  });

  it("sanitizes Supabase RPC errors in HTTP responses", async () => {
    const supabase = {
      rpc: vi.fn().mockResolvedValue({
        data: null,
        error: { message: 'relation "private_table" does not exist at line 1' },
      }),
    };

    const response = await handleInternalProcessDueRounds(processRequest(SECRET), {
      getInternalJobSecret: () => SECRET,
      getSupabaseAdmin: () => supabase,
      allowNowOverride: false,
    });

    expect(response.status).toBe(500);
    expect(await response.json()).toEqual({ error: "internal_job_failed" });
  });
});

describe("sanitizeOperationalError", () => {
  it("does not expose stack traces or SQL text", () => {
    expect(sanitizeOperationalError(new Error("select * from private_table\nstack"))).toBe(
      "internal_job_failed",
    );
  });
});
