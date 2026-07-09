import { z } from "zod";

type RpcResult = {
  data: unknown;
  error: { message: string } | null;
};

export type ProcessJobClient = {
  rpc: (fn: string, args?: Record<string, unknown>) => Promise<RpcResult>;
};

export type RetryJobClient = {
  rpc: (fn: string, args?: Record<string, unknown>) => Promise<RpcResult>;
};

type ProcessDeps = {
  getInternalJobSecret: () => string | undefined;
  getSupabaseAdmin: () => ProcessJobClient;
  allowNowOverride: boolean;
};

type RetryDeps = {
  getInternalJobSecret: () => string | undefined;
  getSupabaseAdmin: () => RetryJobClient;
};

const processInput = z
  .object({
    _now: z.string().datetime({ offset: true }).optional(),
  })
  .strict()
  .optional();

const retryInput = z
  .object({
    job_run_id: z.string().uuid(),
  })
  .strict();

function json(data: unknown, status = 200): Response {
  return Response.json(data, { status });
}

function readBearerToken(request: Request): string | null {
  const header = request.headers.get("authorization");
  if (!header?.startsWith("Bearer ")) return null;
  const token = header.slice("Bearer ".length);
  return token.length > 0 ? token : null;
}

function constantTimeEqual(left: string, right: string): boolean {
  const encoder = new TextEncoder();
  const leftBytes = encoder.encode(left);
  const rightBytes = encoder.encode(right);
  const length = Math.max(leftBytes.length, rightBytes.length);
  let diff = leftBytes.length ^ rightBytes.length;

  for (let index = 0; index < length; index += 1) {
    diff |= (leftBytes[index] ?? 0) ^ (rightBytes[index] ?? 0);
  }

  return diff === 0;
}

function isAuthorized(request: Request, expectedSecret: string | undefined): boolean {
  if (!expectedSecret) return false;
  const token = readBearerToken(request);
  if (!token) return false;
  return constantTimeEqual(token, expectedSecret);
}

async function readOptionalJson(request: Request): Promise<unknown> {
  const text = await request.text();
  if (!text.trim()) return undefined;
  return JSON.parse(text);
}

export function sanitizeOperationalError(_error: unknown): string {
  return "internal_job_failed";
}

export async function handleInternalProcessDueRounds(
  request: Request,
  deps: ProcessDeps,
): Promise<Response> {
  if (!isAuthorized(request, deps.getInternalJobSecret())) {
    return json({ error: "unauthorized" }, 401);
  }

  let input: z.infer<typeof processInput>;
  try {
    input = processInput.parse(await readOptionalJson(request));
  } catch {
    return json({ error: "invalid_payload" }, 400);
  }

  const args =
    deps.allowNowOverride && input?._now
      ? {
          _now: input._now,
        }
      : {};

  const { data, error } = await deps.getSupabaseAdmin().rpc("process_due_rounds", args);
  if (error) {
    return json({ error: sanitizeOperationalError(error) }, 500);
  }

  return json({ result: data });
}

export async function retryOperationalJobRun(
  client: RetryJobClient,
  jobRunId: string,
): Promise<unknown> {
  const { data, error } = await client.rpc("_operational_retry_job_run", {
    _job_run_id: jobRunId,
  });

  if (error) throw new Error(error.message);
  return data;
}

export async function handleInternalRetryJob(request: Request, deps: RetryDeps): Promise<Response> {
  if (!isAuthorized(request, deps.getInternalJobSecret())) {
    return json({ error: "unauthorized" }, 401);
  }

  let input: z.infer<typeof retryInput>;
  try {
    input = retryInput.parse(await readOptionalJson(request));
  } catch {
    return json({ error: "invalid_payload" }, 400);
  }

  try {
    const result = await retryOperationalJobRun(deps.getSupabaseAdmin(), input.job_run_id);
    return json({ result });
  } catch (error) {
    const message = error instanceof Error ? error.message : String(error);
    if (message.includes("job_run_not_retryable")) {
      return json({ error: "job_run_not_retryable" }, 409);
    }
    return json({ error: sanitizeOperationalError(error) }, 500);
  }
}
