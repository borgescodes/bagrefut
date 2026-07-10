import { z } from "zod";
import { PLAYER_ATTRIBUTE_KEYS, PLAYER_SECTORS } from "@/domain/enums";
import type {
  PlayerAttributeKey,
  PlayerPosition,
  PlayerRarity,
  PlayerSector,
} from "@/domain/enums";
import { centsToReal } from "@/domain/rules/validators";

export const MIN_ROSTER_SIZE = 5;
export const MAX_ROSTER_SIZE = 10;
export const MAX_MARKET_PRICE_CENTS = 10_000;
export const MAX_WALLET_CENTS = 99_999;

export const MARKET_QUERY_KEYS = [
  "marketWorkspace",
  "myRoster",
  "systemMarket",
  "p2pListings",
  "transferOffers",
  "tradeTargets",
] as const;

export const playerPositionSchema = z.enum(["GK", "DEF", "MID", "ATA"]);
export const playerRaritySchema = z.enum(["peba", "paia", "pika"]);
export const playerSectorSchema = z.enum(PLAYER_SECTORS);
export const playerAttributeSchema = z.enum(PLAYER_ATTRIBUTE_KEYS);

const uuidSchema = z.string().uuid();
const transactionMoneySchema = z.number().int().min(0).max(MAX_MARKET_PRICE_CENTS);

export const clubPlayerInputSchema = z.object({ clubPlayerId: uuidSchema });
export const trainClubPlayerInputSchema = clubPlayerInputSchema.extend({
  attribute: playerAttributeSchema,
});
export const listingIdInputSchema = z.object({ listingId: uuidSchema });
export const offerIdInputSchema = z.object({ offerId: uuidSchema });
export const tradeTargetInputSchema = z.object({ clubId: uuidSchema });

export const p2pMarketFiltersSchema = z.object({
  position: playerPositionSchema.nullish(),
  rarity: playerRaritySchema.nullish(),
  minOverall: z.number().int().min(1).max(99).nullish(),
  maxOverall: z.number().int().min(1).max(99).nullish(),
  maxPriceCents: transactionMoneySchema.nullish(),
});

export const createListingInputSchema = z.object({
  clubPlayerId: uuidSchema,
  priceCents: z.number().int().min(1).max(MAX_MARKET_PRICE_CENTS),
});

export const createTransferOfferInputSchema = z
  .object({
    toClubId: uuidSchema,
    fromClubPlayerIds: z.array(uuidSchema).max(5),
    toClubPlayerIds: z.array(uuidSchema).max(5),
    cashCents: transactionMoneySchema,
    expiresAt: z.string().datetime(),
  })
  .superRefine((value, context) => {
    if (new Set(value.fromClubPlayerIds).size !== value.fromClubPlayerIds.length) {
      context.addIssue({
        code: z.ZodIssueCode.custom,
        path: ["fromClubPlayerIds"],
        message: "duplicate_player",
      });
    }
    if (new Set(value.toClubPlayerIds).size !== value.toClubPlayerIds.length) {
      context.addIssue({
        code: z.ZodIssueCode.custom,
        path: ["toClubPlayerIds"],
        message: "duplicate_player",
      });
    }
    if (
      value.fromClubPlayerIds.length === 0 &&
      value.toClubPlayerIds.length === 0 &&
      value.cashCents === 0
    ) {
      context.addIssue({ code: z.ZodIssueCode.custom, message: "offer_empty" });
    }
    if (new Date(value.expiresAt).getTime() <= Date.now()) {
      context.addIssue({
        code: z.ZodIssueCode.custom,
        path: ["expiresAt"],
        message: "offer_expired",
      });
    }
  });

export interface PlayerAttributes {
  velocity: number;
  finishing: number;
  passing: number;
  dribbling: number;
  defending: number;
  physical: number;
  goalkeeping: number;
}

export interface AttributeProgress {
  attribute: PlayerAttributeKey;
  progress: number;
  updatedAt: string;
}

export interface MarketCardSummary {
  clubPlayerId: string;
  playerId: string;
  name: string;
  position: PlayerPosition;
  rarity: PlayerRarity;
  sector: PlayerSector;
  overall: number;
  referenceValueCents: number;
  priceCents: number;
  attributes: PlayerAttributes;
}

export interface RosterMarketCard extends MarketCardSummary {
  acquiredAt: string;
  isReserved: boolean;
  systemSalePriceCents: number;
  trainingCostCents: number;
  attributeProgress: AttributeProgress[];
}

export interface SystemMarketCard extends MarketCardSummary {
  acquiredAt: string;
  isAvailable: boolean;
}

export interface P2PMarketListing extends MarketCardSummary {
  listingId: string;
  sellerClubId: string;
  sellerName: string;
  sellerAbbreviation: string;
  createdAt: string;
  isMine: boolean;
}

export type TransferOfferCard = Omit<MarketCardSummary, "priceCents">;

export interface TransferOfferSummary {
  offerId: string;
  direction: "incoming" | "outgoing";
  status: "pending" | "accepted" | "rejected" | "cancelled" | "expired";
  fromClub: { id: string; name: string; abbreviation: string };
  toClub: { id: string; name: string; abbreviation: string };
  cashCents: number;
  createdAt: string;
  expiresAt: string;
  resolvedAt: string | null;
  fromCards: TransferOfferCard[];
  toCards: TransferOfferCard[];
  canAccept: boolean;
  canReject: boolean;
  canCancel: boolean;
}

export interface TradeTarget {
  clubId: string;
  name: string;
  abbreviation: string;
  rosterSize: number;
}

export interface MarketFilters {
  search: string;
  position: PlayerPosition | null;
  rarity: PlayerRarity | null;
  sector: PlayerSector | null;
  minOverall: number | null;
  maxOverall: number | null;
  sortBy: "name" | "overall" | "price";
  sortDirection: "asc" | "desc";
}

export function filterAndSortMarketCards<T extends MarketCardSummary>(
  cards: readonly T[],
  filters: MarketFilters,
): T[] {
  const search = normalizeSearch(filters.search);
  const direction = filters.sortDirection === "asc" ? 1 : -1;

  return cards
    .filter((card) => {
      if (search && !normalizeSearch(card.name).includes(search)) return false;
      if (filters.position && card.position !== filters.position) return false;
      if (filters.rarity && card.rarity !== filters.rarity) return false;
      if (filters.sector && card.sector !== filters.sector) return false;
      if (filters.minOverall !== null && card.overall < filters.minOverall) return false;
      if (filters.maxOverall !== null && card.overall > filters.maxOverall) return false;
      return true;
    })
    .sort((left, right) => {
      if (filters.sortBy === "name") {
        return left.name.localeCompare(right.name, "pt-BR") * direction;
      }
      const leftValue = filters.sortBy === "overall" ? left.overall : left.priceCents;
      const rightValue = filters.sortBy === "overall" ? right.overall : right.priceCents;
      return (leftValue - rightValue || left.name.localeCompare(right.name, "pt-BR")) * direction;
    });
}

export function formatMarketPrice(cents: number): string {
  return centsToReal(cents);
}

export function projectBalanceAfter(balanceCents: number, debitCents: number): number {
  return balanceCents - debitCents;
}

export function isRosterWithinLimits(size: number): boolean {
  return size >= MIN_ROSTER_SIZE && size <= MAX_ROSTER_SIZE;
}

export function projectTradeRosters(input: {
  fromRosterSize: number;
  toRosterSize: number;
  fromCards: number;
  toCards: number;
}): { fromRosterSize: number; toRosterSize: number; isValid: boolean } {
  const fromRosterSize = input.fromRosterSize - input.fromCards + input.toCards;
  const toRosterSize = input.toRosterSize - input.toCards + input.fromCards;
  return {
    fromRosterSize,
    toRosterSize,
    isValid: isRosterWithinLimits(fromRosterSize) && isRosterWithinLimits(toRosterSize),
  };
}

export function canSubmitMarketAction(input: { isPending: boolean; isValid: boolean }): boolean {
  return input.isValid && !input.isPending;
}

interface MarketQueryClient {
  invalidateQueries(input: { queryKey: readonly [string] }): Promise<unknown>;
}

export async function invalidateMarketQueries(queryClient: MarketQueryClient): Promise<void> {
  await Promise.all(
    MARKET_QUERY_KEYS.map((queryKey) => queryClient.invalidateQueries({ queryKey: [queryKey] })),
  );
}

function normalizeSearch(value: string): string {
  return value
    .normalize("NFD")
    .replace(/[\u0300-\u036f]/g, "")
    .trim()
    .toLocaleLowerCase("pt-BR");
}
