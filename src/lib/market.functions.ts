import type { SupabaseClient } from "@supabase/supabase-js";
import { createServerFn } from "@tanstack/react-start";
import { z } from "zod";
import {
  systemBuyPriceCents,
  systemSellPriceCents,
  trainingCostCents,
} from "@/domain/calculators/prices";
import {
  clubPlayerInputSchema,
  createListingInputSchema,
  createTransferOfferInputSchema,
  listingIdInputSchema,
  offerIdInputSchema,
  p2pMarketFiltersSchema,
  tradeTargetInputSchema,
  trainClubPlayerInputSchema,
} from "@/domain/market";
import type {
  P2PMarketListing,
  MarketCardSummary,
  PlayerAttributes,
  RosterMarketCard,
  SystemMarketCard,
  TradeTarget,
  TransferOfferCard,
  TransferOfferSummary,
} from "@/domain/market";
import { requireSupabaseAuth } from "@/integrations/supabase/auth-middleware";
import type { Database } from "@/integrations/supabase/types";
import { mapMarketErrorMessage } from "@/lib/market-errors";

const playerSchema = z.object({
  id: z.string().uuid(),
  code: z.string().min(1),
  name: z.string(),
  position: z.enum(["GK", "DEF", "MID", "ATA"]),
  rarity: z.enum(["peba", "paia", "pika"]),
  sector: z.enum([
    "centro",
    "cidade_nova",
    "promissao",
    "jaderlandia",
    "uraim",
    "jardim",
    "flamboyant",
    "angelim",
    "camboata",
    "buriti",
    "laercio",
    "bela_vista",
    "nagibao",
    "ipixuna",
    "caipe",
    "paulo_sexto",
    "morada_do_sol",
    "morada_do_vento",
    "nova_conquista",
  ]),
  overall: z.number(),
  velocity: z.number(),
  finishing: z.number(),
  passing: z.number(),
  dribbling: z.number(),
  defending: z.number(),
  physical: z.number(),
  goalkeeping: z.number(),
  reference_value_cents: z.number().int(),
});

const progressSchema = z.object({
  attribute: z.enum([
    "velocity",
    "finishing",
    "passing",
    "dribbling",
    "defending",
    "physical",
    "goalkeeping",
  ]),
  progress: z.number().int().min(0).max(2),
  updated_at: z.string(),
});

const rosterRowSchema = z.object({
  id: z.string().uuid(),
  acquired_at: z.string(),
  is_reserved: z.boolean(),
  players: playerSchema.nullable(),
  club_player_attribute_progress: z.array(progressSchema).nullable(),
});

const stockRowSchema = z.object({
  acquired_at: z.string(),
  club_player_id: z.string().uuid(),
  club_players: z
    .object({
      id: z.string().uuid(),
      club_id: z.string().uuid().nullable(),
      is_reserved: z.boolean(),
      players: playerSchema.nullable(),
    })
    .nullable(),
});

const listingRowSchema = z.object({
  listing_id: z.string().uuid(),
  seller_club_id: z.string().uuid(),
  seller_name: z.string(),
  seller_abbreviation: z.string(),
  club_player_id: z.string().uuid(),
  player_id: z.string().uuid(),
  player_code: z.string().min(1),
  player_name: z.string(),
  position: z.enum(["GK", "DEF", "MID", "ATA"]),
  rarity: z.enum(["peba", "paia", "pika"]),
  sector: playerSchema.shape.sector,
  overall: z.number(),
  velocity: z.number(),
  finishing: z.number(),
  passing: z.number(),
  dribbling: z.number(),
  defending: z.number(),
  physical: z.number(),
  goalkeeping: z.number(),
  reference_value_cents: z.number().int(),
  price_cents: z.number().int(),
  created_at: z.string(),
  is_mine: z.boolean(),
});

const offerCardSchema = listingRowSchema.pick({
  club_player_id: true,
  player_id: true,
  player_code: true,
  player_name: true,
  position: true,
  rarity: true,
  sector: true,
  overall: true,
  velocity: true,
  finishing: true,
  passing: true,
  dribbling: true,
  defending: true,
  physical: true,
  goalkeeping: true,
  reference_value_cents: true,
});

const clubSummarySchema = z.object({
  id: z.string().uuid(),
  name: z.string(),
  abbreviation: z.string(),
});

const offerRowSchema = z.object({
  offer_id: z.string().uuid(),
  direction: z.enum(["incoming", "outgoing"]),
  status: z.enum(["pending", "accepted", "rejected", "cancelled", "expired"]),
  from_club: clubSummarySchema,
  to_club: clubSummarySchema,
  cash_cents: z.number().int(),
  created_at: z.string(),
  expires_at: z.string(),
  resolved_at: z.string().nullable(),
  from_cards: z.array(offerCardSchema),
  to_cards: z.array(offerCardSchema),
  can_accept: z.boolean(),
  can_reject: z.boolean(),
  can_cancel: z.boolean(),
});

const tradeTargetSchema = z.object({
  club_id: z.string().uuid(),
  name: z.string(),
  abbreviation: z.string(),
  roster_size: z.number().int(),
});

const listingMutationResultSchema = z
  .array(
    z.object({
      listing_id: z.string().uuid(),
      status: z.enum(["open", "sold", "cancelled", "expired"]),
      club_player_id: z.string().uuid(),
      price_cents: z.number().int(),
      is_reserved: z.boolean(),
      idempotent: z.boolean(),
    }),
  )
  .min(1);

const listingPurchaseResultSchema = z
  .array(
    z.object({
      listing_id: z.string().uuid(),
      status: z.literal("sold"),
      club_player_id: z.string().uuid(),
      price_cents: z.number().int(),
      buyer_balance_cents: z.number().int(),
      seller_balance_cents: z.number().int(),
      buyer_roster_size: z.number().int(),
      seller_roster_size: z.number().int(),
      idempotent: z.boolean(),
    }),
  )
  .min(1);

const createOfferResultSchema = z
  .array(
    z.object({
      offer_id: z.string().uuid(),
      status: z.literal("pending"),
      expires_at: z.string(),
      reserved_count: z.number().int(),
      idempotent: z.boolean(),
    }),
  )
  .min(1);

const offerMutationResultSchema = z
  .array(
    z.object({
      offer_id: z.string().uuid(),
      status: z.enum(["accepted", "rejected", "cancelled"]),
      resolved_at: z.string(),
      idempotent: z.boolean(),
    }),
  )
  .min(1);

export const getMyRoster = createServerFn({ method: "GET" })
  .middleware([requireSupabaseAuth])
  .handler(async ({ context }) => loadRoster(context.supabase));

export const listSystemMarketStock = createServerFn({ method: "GET" })
  .middleware([requireSupabaseAuth])
  .handler(async ({ context }) => loadSystemMarket(context.supabase));

export const getMarketWorkspace = createServerFn({ method: "GET" })
  .middleware([requireSupabaseAuth])
  .handler(async ({ context }) => {
    const [clubResult, roster, systemMarket] = await Promise.all([
      context.supabase
        .from("clubs")
        .select("id, name, abbreviation, balance_cents")
        .eq("owner_id", context.userId)
        .maybeSingle(),
      loadRoster(context.supabase),
      loadSystemMarket(context.supabase),
    ]);
    if (clubResult.error) throw new Error(mapMarketErrorMessage(clubResult.error));
    return { club: clubResult.data, roster, systemMarket };
  });

export const buyPlayerFromSystem = createServerFn({ method: "POST" })
  .middleware([requireSupabaseAuth])
  .validator((data: unknown) => clubPlayerInputSchema.parse(data))
  .handler(async ({ data, context }) => {
    const { data: result, error } = await context.supabase.rpc("buy_player_from_system", {
      _club_player_id: data.clubPlayerId,
    });
    if (error) throw new Error(mapMarketErrorMessage(error));
    return { result: result?.[0] ?? null };
  });

export const sellPlayerToSystem = createServerFn({ method: "POST" })
  .middleware([requireSupabaseAuth])
  .validator((data: unknown) => clubPlayerInputSchema.parse(data))
  .handler(async ({ data, context }) => {
    const { data: result, error } = await context.supabase.rpc("sell_player_to_system", {
      _club_player_id: data.clubPlayerId,
    });
    if (error) throw new Error(mapMarketErrorMessage(error));
    return { result: result?.[0] ?? null };
  });

export const trainClubPlayer = createServerFn({ method: "POST" })
  .middleware([requireSupabaseAuth])
  .validator((data: unknown) => trainClubPlayerInputSchema.parse(data))
  .handler(async ({ data, context }) => {
    const { data: result, error } = await context.supabase.rpc("train_club_player", {
      _club_player_id: data.clubPlayerId,
      _attribute: data.attribute,
    });
    if (error) throw new Error(mapMarketErrorMessage(error));
    return { result: result?.[0] ?? null };
  });

export const listP2PMarket = createServerFn({ method: "GET" })
  .middleware([requireSupabaseAuth])
  .validator((data: unknown) => p2pMarketFiltersSchema.parse(data ?? {}))
  .handler(async ({ data, context }) => {
    const rows = await callMarketRpc(
      context.supabase,
      "list_market_listings",
      {
        _position: data.position ?? null,
        _rarity: data.rarity ?? null,
        _min_overall: data.minOverall ?? null,
        _max_overall: data.maxOverall ?? null,
        _max_price_cents: data.maxPriceCents ?? null,
      },
      z.array(listingRowSchema),
    );
    return rows.map(mapListing);
  });

export const createMarketListing = createServerFn({ method: "POST" })
  .middleware([requireSupabaseAuth])
  .validator((data: unknown) => createListingInputSchema.parse(data))
  .handler(async ({ data, context }) => ({
    result: (
      await callMarketRpc(
        context.supabase,
        "create_market_listing",
        { _club_player_id: data.clubPlayerId, _price_cents: data.priceCents },
        listingMutationResultSchema,
      )
    )[0],
  }));

export const cancelMarketListing = createServerFn({ method: "POST" })
  .middleware([requireSupabaseAuth])
  .validator((data: unknown) => listingIdInputSchema.parse(data))
  .handler(async ({ data, context }) => ({
    result: (
      await callMarketRpc(
        context.supabase,
        "cancel_market_listing",
        { _listing_id: data.listingId },
        listingMutationResultSchema,
      )
    )[0],
  }));

export const buyMarketListing = createServerFn({ method: "POST" })
  .middleware([requireSupabaseAuth])
  .validator((data: unknown) => listingIdInputSchema.parse(data))
  .handler(async ({ data, context }) => ({
    result: (
      await callMarketRpc(
        context.supabase,
        "buy_market_listing",
        { _listing_id: data.listingId },
        listingPurchaseResultSchema,
      )
    )[0],
  }));

export const listMyTransferOffers = createServerFn({ method: "GET" })
  .middleware([requireSupabaseAuth])
  .handler(async ({ context }) => {
    const rows = await callMarketRpc(
      context.supabase,
      "list_my_transfer_offers",
      {},
      z.array(offerRowSchema),
    );
    return rows.map(mapOffer);
  });

export const createTransferOffer = createServerFn({ method: "POST" })
  .middleware([requireSupabaseAuth])
  .validator((data: unknown) => createTransferOfferInputSchema.parse(data))
  .handler(async ({ data, context }) => ({
    result: (
      await callMarketRpc(
        context.supabase,
        "create_transfer_offer",
        {
          _to_club_id: data.toClubId,
          _from_club_player_ids: data.fromClubPlayerIds,
          _to_club_player_ids: data.toClubPlayerIds,
          _cash_cents: data.cashCents,
          _expires_at: data.expiresAt,
        },
        createOfferResultSchema,
      )
    )[0],
  }));

export const acceptTransferOffer = offerMutation("accept_transfer_offer");
export const rejectTransferOffer = offerMutation("reject_transfer_offer");
export const cancelTransferOffer = offerMutation("cancel_transfer_offer");

export const listTradeTargets = createServerFn({ method: "GET" })
  .middleware([requireSupabaseAuth])
  .handler(async ({ context }) => {
    const rows = await callMarketRpc(
      context.supabase,
      "list_trade_targets",
      {},
      z.array(tradeTargetSchema),
    );
    return rows.map(
      (row): TradeTarget => ({
        clubId: row.club_id,
        name: row.name,
        abbreviation: row.abbreviation,
        rosterSize: row.roster_size,
      }),
    );
  });

export const getTradeTargetRoster = createServerFn({ method: "GET" })
  .middleware([requireSupabaseAuth])
  .validator((data: unknown) => tradeTargetInputSchema.parse(data))
  .handler(async ({ data, context }) => {
    const rows = await callMarketRpc(
      context.supabase,
      "get_trade_target_roster",
      { _club_id: data.clubId },
      z.array(offerCardSchema),
    );
    return rows.map(mapOfferCard);
  });

function offerMutation(
  rpcName: "accept_transfer_offer" | "reject_transfer_offer" | "cancel_transfer_offer",
) {
  return createServerFn({ method: "POST" })
    .middleware([requireSupabaseAuth])
    .validator((data: unknown) => offerIdInputSchema.parse(data))
    .handler(async ({ data, context }) => ({
      result: (
        await callMarketRpc(
          context.supabase,
          rpcName,
          { _offer_id: data.offerId },
          offerMutationResultSchema,
        )
      )[0],
    }));
}

async function loadRoster(supabase: SupabaseClient<Database>): Promise<RosterMarketCard[]> {
  const { data, error } = await supabase
    .from("club_players")
    .select(
      `
        id,
        acquired_at,
        is_reserved,
        players (
          id, code, name, position, rarity, sector, overall,
          velocity, finishing, passing, dribbling, defending, physical, goalkeeping,
          reference_value_cents
        ),
        club_player_attribute_progress (attribute, progress, updated_at)
      `,
    )
    .order("acquired_at", { ascending: true });
  if (error) throw new Error(mapMarketErrorMessage(error));
  return z
    .array(rosterRowSchema)
    .parse(data ?? [])
    .flatMap((row) => {
      if (!row.players) return [];
      return [
        {
          ...mapPlayer(row.id, row.players, systemBuyPriceCents(row.players.reference_value_cents)),
          acquiredAt: row.acquired_at,
          isReserved: row.is_reserved,
          systemSalePriceCents: systemBuyPriceCents(row.players.reference_value_cents),
          trainingCostCents: trainingCostCents(row.players.rarity),
          attributeProgress: (row.club_player_attribute_progress ?? []).map((progress) => ({
            attribute: progress.attribute,
            progress: progress.progress,
            updatedAt: progress.updated_at,
          })),
        },
      ];
    });
}

async function loadSystemMarket(supabase: SupabaseClient<Database>): Promise<SystemMarketCard[]> {
  const { data, error } = await supabase
    .from("system_market_stock")
    .select(
      `
        club_player_id,
        acquired_at,
        club_players (
          id, club_id, is_reserved,
          players (
            id, name, position, rarity, sector, overall,
            velocity, finishing, passing, dribbling, defending, physical, goalkeeping,
            reference_value_cents
          )
        )
      `,
    )
    .order("acquired_at", { ascending: true });
  if (error) throw new Error(mapMarketErrorMessage(error));
  return z
    .array(stockRowSchema)
    .parse(data ?? [])
    .flatMap((row) => {
      const card = row.club_players;
      if (!card?.players) return [];
      return [
        {
          ...mapPlayer(
            row.club_player_id,
            card.players,
            systemSellPriceCents(card.players.reference_value_cents),
          ),
          acquiredAt: row.acquired_at,
          isAvailable: card.club_id === null && !card.is_reserved,
        },
      ];
    });
}

type ParsedPlayer = z.infer<typeof playerSchema>;

function mapPlayer(
  clubPlayerId: string,
  player: ParsedPlayer,
  priceCents: number,
): MarketCardSummary {
  return {
    clubPlayerId,
    playerId: player.id,
    code: player.code,
    name: player.name,
    position: player.position,
    rarity: player.rarity,
    sector: player.sector,
    overall: player.overall,
    referenceValueCents: player.reference_value_cents,
    priceCents,
    attributes: attributesFrom(player),
  };
}

function mapListing(row: z.infer<typeof listingRowSchema>): P2PMarketListing {
  return {
    ...mapOfferCard(row),
    priceCents: row.price_cents,
    listingId: row.listing_id,
    sellerClubId: row.seller_club_id,
    sellerName: row.seller_name,
    sellerAbbreviation: row.seller_abbreviation,
    createdAt: row.created_at,
    isMine: row.is_mine,
  };
}

function mapOfferCard(row: z.infer<typeof offerCardSchema>): TransferOfferCard {
  return {
    clubPlayerId: row.club_player_id,
    playerId: row.player_id,
    code: row.player_code,
    name: row.player_name,
    position: row.position,
    rarity: row.rarity,
    sector: row.sector,
    overall: row.overall,
    referenceValueCents: row.reference_value_cents,
    attributes: attributesFrom(row),
  };
}

function mapOffer(row: z.infer<typeof offerRowSchema>): TransferOfferSummary {
  return {
    offerId: row.offer_id,
    direction: row.direction,
    status: row.status,
    fromClub: row.from_club,
    toClub: row.to_club,
    cashCents: row.cash_cents,
    createdAt: row.created_at,
    expiresAt: row.expires_at,
    resolvedAt: row.resolved_at,
    fromCards: row.from_cards.map(mapOfferCard),
    toCards: row.to_cards.map(mapOfferCard),
    canAccept: row.can_accept,
    canReject: row.can_reject,
    canCancel: row.can_cancel,
  };
}

function attributesFrom(row: PlayerAttributes): PlayerAttributes {
  return {
    velocity: row.velocity,
    finishing: row.finishing,
    passing: row.passing,
    dribbling: row.dribbling,
    defending: row.defending,
    physical: row.physical,
    goalkeeping: row.goalkeeping,
  };
}

type UntypedRpcResult = {
  data: unknown;
  error: { message: string } | null;
};

async function callMarketRpc<T>(
  supabase: SupabaseClient<Database>,
  functionName: string,
  args: Record<string, unknown>,
  resultSchema: z.ZodType<T>,
): Promise<T> {
  const rpc = supabase.rpc as unknown as (
    name: string,
    parameters: Record<string, unknown>,
  ) => PromiseLike<UntypedRpcResult>;
  const { data, error } = await rpc(functionName, args);
  if (error) throw new Error(mapMarketErrorMessage(error));
  const parsed = resultSchema.safeParse(data);
  if (!parsed.success) {
    throw new Error("Não foi possível validar a resposta do mercado.");
  }
  return parsed.data;
}
