import type { SupabaseClient } from "@supabase/supabase-js";
import { describe, expect, it, vi } from "vitest";
import type { Database } from "@/integrations/supabase/types";

type ServerFnChain = {
  middleware: () => ServerFnChain;
  validator: () => ServerFnChain;
  handler: (handler: unknown) => unknown;
};

vi.mock("@tanstack/react-start", () => ({
  createServerFn: () => {
    const chain = {} as ServerFnChain;
    chain.middleware = () => chain;
    chain.validator = () => chain;
    chain.handler = (handler: unknown) => handler;
    return chain;
  },
}));

vi.mock("@/integrations/supabase/auth-middleware", () => ({
  requireSupabaseAuth: {},
}));

import { loadRoster, loadSystemMarket } from "@/lib/market.functions";

type QueryResult = {
  data: unknown[];
  error: null;
};

function createQueryClient(result: QueryResult = { data: [], error: null }) {
  const builder: Record<string, unknown> = {};
  const select = vi.fn(() => builder);
  const eq = vi.fn(() => builder);
  const order = vi.fn(() => builder);

  Object.assign(builder, {
    select,
    eq,
    order,
    then: (resolve: (value: QueryResult) => unknown, reject?: (reason: unknown) => unknown) =>
      Promise.resolve(result).then(resolve, reject),
  });

  const from = vi.fn(() => builder);
  const supabase = { from } as unknown as SupabaseClient<Database>;

  return { supabase, from, eq, order };
}

describe("market server query scope", () => {
  it("filters roster by authenticated club id even when RLS can read more rows", async () => {
    const query = createQueryClient();
    const clubId = "00000000-0000-0000-0000-000000000123";

    await loadRoster(query.supabase, clubId);

    expect(query.from).toHaveBeenCalledWith("club_players");
    expect(query.eq).toHaveBeenCalledWith("club_id", clubId);
    expect(query.order).toHaveBeenCalledWith("acquired_at", { ascending: true });
  });

  it("filters system market to commercial stock even for admin", async () => {
    const query = createQueryClient();

    await loadSystemMarket(query.supabase);

    expect(query.from).toHaveBeenCalledWith("system_market_stock");
    expect(query.eq).toHaveBeenCalledWith("is_market_eligible", true);
    expect(query.order).toHaveBeenCalledWith("acquired_at", { ascending: true });
  });
});
