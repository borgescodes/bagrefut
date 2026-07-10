import { describe, expect, it, vi } from "vitest";
import {
  MARKET_QUERY_KEYS,
  MAX_MARKET_PRICE_CENTS,
  MAX_ROSTER_SIZE,
  MAX_WALLET_CENTS,
  MIN_ROSTER_SIZE,
  canSubmitMarketAction,
  createListingInputSchema,
  createTransferOfferInputSchema,
  filterAndSortMarketCards,
  formatMarketPrice,
  invalidateMarketQueries,
  isRosterWithinLimits,
  projectBalanceAfter,
  projectTradeRosters,
  type MarketCardSummary,
} from "@/domain/market";
import { mapMarketErrorMessage } from "@/lib/market-errors";

const cards: MarketCardSummary[] = [
  {
    clubPlayerId: "00000000-0000-0000-0000-000000000001",
    playerId: "10000000-0000-0000-0000-000000000001",
    name: "Zagueiro Centro",
    position: "DEF",
    rarity: "paia",
    sector: "centro",
    overall: 70,
    referenceValueCents: 1_500,
    priceCents: 1_300,
    attributes: {
      velocity: 60,
      finishing: 30,
      passing: 62,
      dribbling: 55,
      defending: 78,
      physical: 75,
      goalkeeping: 10,
    },
  },
  {
    clubPlayerId: "00000000-0000-0000-0000-000000000002",
    playerId: "10000000-0000-0000-0000-000000000002",
    name: "Atacante Promessa",
    position: "ATA",
    rarity: "pika",
    sector: "promissao",
    overall: 82,
    referenceValueCents: 5_500,
    priceCents: 6_000,
    attributes: {
      velocity: 84,
      finishing: 87,
      passing: 71,
      dribbling: 82,
      defending: 30,
      physical: 78,
      goalkeeping: 8,
    },
  },
  {
    clubPlayerId: "00000000-0000-0000-0000-000000000003",
    playerId: "10000000-0000-0000-0000-000000000003",
    name: "Goleiro Cidade Nova",
    position: "GK",
    rarity: "peba",
    sector: "cidade_nova",
    overall: 55,
    referenceValueCents: 300,
    priceCents: 250,
    attributes: {
      velocity: 40,
      finishing: 10,
      passing: 45,
      dribbling: 35,
      defending: 52,
      physical: 58,
      goalkeeping: 64,
    },
  },
];

describe("market filters and sorting", () => {
  it("combines name, position, rarity, sector and overall filters", () => {
    expect(
      filterAndSortMarketCards(cards, {
        search: "zagueiro",
        position: "DEF",
        rarity: "paia",
        sector: "centro",
        minOverall: 65,
        maxOverall: 75,
        sortBy: "name",
        sortDirection: "asc",
      }).map((card) => card.name),
    ).toEqual(["Zagueiro Centro"]);
  });

  it("sorts by name, overall and price in both directions", () => {
    const base = {
      search: "",
      position: null,
      rarity: null,
      sector: null,
      minOverall: null,
      maxOverall: null,
    } as const;

    expect(
      filterAndSortMarketCards(cards, {
        ...base,
        sortBy: "name",
        sortDirection: "asc",
      }).map((card) => card.name),
    ).toEqual(["Atacante Promessa", "Goleiro Cidade Nova", "Zagueiro Centro"]);
    expect(
      filterAndSortMarketCards(cards, {
        ...base,
        sortBy: "overall",
        sortDirection: "desc",
      }).map((card) => card.overall),
    ).toEqual([82, 70, 55]);
    expect(
      filterAndSortMarketCards(cards, {
        ...base,
        sortBy: "price",
        sortDirection: "asc",
      }).map((card) => card.priceCents),
    ).toEqual([250, 1_300, 6_000]);
  });
});

describe("closed market limits", () => {
  it("uses roster 5-10, transaction R$ 100 and wallet R$ 999,99", () => {
    expect(MIN_ROSTER_SIZE).toBe(5);
    expect(MAX_ROSTER_SIZE).toBe(10);
    expect(MAX_MARKET_PRICE_CENTS).toBe(10_000);
    expect(MAX_WALLET_CENTS).toBe(99_999);
    expect(isRosterWithinLimits(5)).toBe(true);
    expect(isRosterWithinLimits(10)).toBe(true);
    expect(isRosterWithinLimits(4)).toBe(false);
    expect(isRosterWithinLimits(11)).toBe(false);
  });

  it("projects balances without hiding an invalid negative result", () => {
    expect(projectBalanceAfter(2_000, 750)).toBe(1_250);
    expect(projectBalanceAfter(500, 750)).toBe(-250);
  });

  it("accepts 1x1 and rejects any trade producing fewer than 5 or more than 10 cards", () => {
    expect(
      projectTradeRosters({
        fromRosterSize: 10,
        toRosterSize: 10,
        fromCards: 1,
        toCards: 1,
      }),
    ).toEqual({ fromRosterSize: 10, toRosterSize: 10, isValid: true });

    expect(
      projectTradeRosters({
        fromRosterSize: 10,
        toRosterSize: 10,
        fromCards: 0,
        toCards: 1,
      }).isValid,
    ).toBe(false);

    expect(
      projectTradeRosters({
        fromRosterSize: 5,
        toRosterSize: 10,
        fromCards: 1,
        toCards: 0,
      }).isValid,
    ).toBe(false);
  });
});

describe("market prices and form validators", () => {
  it("formats price in pt-BR using the shared cents contract", () => {
    expect(formatMarketPrice(2_550)).toBe("R$ 25,50");
    expect(formatMarketPrice(MAX_WALLET_CENTS)).toBe("R$ 999,99");
  });

  it("accepts listing prices only from 1 to 10000 cents", () => {
    const id = "00000000-0000-0000-0000-000000000001";
    expect(createListingInputSchema.safeParse({ clubPlayerId: id, priceCents: 1 }).success).toBe(
      true,
    );
    expect(
      createListingInputSchema.safeParse({
        clubPlayerId: id,
        priceCents: MAX_MARKET_PRICE_CENTS,
      }).success,
    ).toBe(true);
    expect(createListingInputSchema.safeParse({ clubPlayerId: id, priceCents: 0 }).success).toBe(
      false,
    );
    expect(
      createListingInputSchema.safeParse({
        clubPlayerId: id,
        priceCents: MAX_MARKET_PRICE_CENTS + 1,
      }).success,
    ).toBe(false);
  });

  it("rejects duplicate cards, more than five cards and empty offers", () => {
    const toClubId = "00000000-0000-0000-0000-000000000010";
    const cardId = "00000000-0000-0000-0000-000000000011";
    const expiresAt = "2027-07-10T12:00:00.000Z";

    expect(
      createTransferOfferInputSchema.safeParse({
        toClubId,
        fromClubPlayerIds: [cardId, cardId],
        toClubPlayerIds: [],
        cashCents: 0,
        expiresAt,
      }).success,
    ).toBe(false);
    expect(
      createTransferOfferInputSchema.safeParse({
        toClubId,
        fromClubPlayerIds: [],
        toClubPlayerIds: [],
        cashCents: 0,
        expiresAt,
      }).success,
    ).toBe(false);
  });
});

describe("market errors and mutation safety", () => {
  it("maps roster and wallet caps to current rules", () => {
    expect(mapMarketErrorMessage(new Error("roster_maximum"))).toBe(
      "O clube pode ter no maximo 10 cartas.",
    );
    expect(mapMarketErrorMessage(new Error("wallet_balance_cap_exceeded"))).toBe(
      "A operacao ultrapassaria o saldo maximo de R$ 999,99.",
    );
  });

  it("maps public contract codes without exposing SQL internals", () => {
    expect(mapMarketErrorMessage(new Error("player_reserved"))).toBe(
      "Esta carta esta reservada em outra negociacao.",
    );
    expect(mapMarketErrorMessage(new Error("daily_training_limit"))).toBe(
      "Seu clube ja treinou hoje. Tente novamente amanha.",
    );
    expect(mapMarketErrorMessage(new Error("duplicate key value violates unique constraint"))).toBe(
      "Nao foi possivel concluir a operacao de mercado.",
    );
  });

  it("prevents a second submission while a mutation is pending", () => {
    expect(canSubmitMarketAction({ isPending: false, isValid: true })).toBe(true);
    expect(canSubmitMarketAction({ isPending: true, isValid: true })).toBe(false);
    expect(canSubmitMarketAction({ isPending: false, isValid: false })).toBe(false);
  });
});

describe("market query invalidation", () => {
  it("invalidates all workspace keys after a successful mutation", async () => {
    const invalidateQueries = vi.fn().mockResolvedValue(undefined);
    await invalidateMarketQueries({ invalidateQueries });

    expect(invalidateQueries).toHaveBeenCalledTimes(MARKET_QUERY_KEYS.length);
    expect(invalidateQueries.mock.calls.map(([input]) => input.queryKey[0])).toEqual(
      MARKET_QUERY_KEYS,
    );
  });
});
