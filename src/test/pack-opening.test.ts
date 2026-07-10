import { describe, expect, it } from "vitest";
import {
  createInitialPackOpeningState,
  getNextRevealState,
  getPackRevealStorageKey,
  parsePackRevealProgress,
  rarityRevealRank,
  sortPackCardsForReveal,
} from "@/domain/pack-opening";
import type { PackOpeningState } from "@/domain/pack-opening";

type TestCard = {
  slot: number;
  player: { overall: number; rarity: "peba" | "paia" | "pika" };
};

function card(slot: number, overall: number, rarity: TestCard["player"]["rarity"]): TestCard {
  return { slot, player: { overall, rarity } };
}

const PACK_ID = "0d4c9f2a-6b1e-4a3d-9c8f-5e7a1b2c3d4e";

describe("rarityRevealRank", () => {
  it("ordena peba < paia < pika", () => {
    expect(rarityRevealRank("peba")).toBeLessThan(rarityRevealRank("paia"));
    expect(rarityRevealRank("paia")).toBeLessThan(rarityRevealRank("pika"));
  });
});

describe("sortPackCardsForReveal", () => {
  it("ordena por overall crescente", () => {
    const sorted = sortPackCardsForReveal([
      card(1, 62, "peba"),
      card(2, 41, "peba"),
      card(3, 55, "peba"),
    ]);
    expect(sorted.map((c) => c.player.overall)).toEqual([41, 55, 62]);
  });

  it("desempata overall igual por raridade peba < paia < pika", () => {
    const sorted = sortPackCardsForReveal([
      card(1, 45, "pika"),
      card(2, 45, "peba"),
      card(3, 45, "paia"),
    ]);
    expect(sorted.map((c) => c.player.rarity)).toEqual(["peba", "paia", "pika"]);
  });

  it("empate completo usa slot crescente (ordenação estável)", () => {
    const sorted = sortPackCardsForReveal([
      card(7, 50, "paia"),
      card(2, 50, "paia"),
      card(5, 50, "paia"),
    ]);
    expect(sorted.map((c) => c.slot)).toEqual([2, 5, 7]);
  });

  it("menor overall primeiro, maior overall por último", () => {
    const sorted = sortPackCardsForReveal([
      card(1, 45, "paia"),
      card(2, 71, "pika"),
      card(3, 33, "peba"),
      card(4, 45, "peba"),
    ]);
    expect(sorted[0].player.overall).toBe(33);
    expect(sorted.at(-1)?.player.overall).toBe(71);
    expect(sorted.map((c) => c.slot)).toEqual([3, 4, 1, 2]);
  });

  it("não muta o array de entrada", () => {
    const input = [card(1, 60, "peba"), card(2, 40, "peba")];
    const snapshot = input.map((c) => c.slot);
    sortPackCardsForReveal(input);
    expect(input.map((c) => c.slot)).toEqual(snapshot);
  });
});

describe("getPackRevealStorageKey", () => {
  it("usa pack.id na chave", () => {
    expect(getPackRevealStorageKey(PACK_ID)).toContain(PACK_ID);
  });

  it("packs diferentes geram chaves diferentes", () => {
    const other = "1a2b3c4d-5e6f-4a7b-8c9d-0e1f2a3b4c5d";
    expect(getPackRevealStorageKey(PACK_ID)).not.toBe(getPackRevealStorageKey(other));
  });
});

describe("parsePackRevealProgress", () => {
  it("aceita progresso válido do mesmo pack", () => {
    const raw = JSON.stringify({ packId: PACK_ID, revealedCount: 4, stage: "revealing" });
    expect(parsePackRevealProgress(raw, PACK_ID)).toEqual({
      packId: PACK_ID,
      revealedCount: 4,
      stage: "revealing",
    });
  });

  it("descarta progresso de outro pack", () => {
    const raw = JSON.stringify({
      packId: "1a2b3c4d-5e6f-4a7b-8c9d-0e1f2a3b4c5d",
      revealedCount: 4,
      stage: "revealing",
    });
    expect(parsePackRevealProgress(raw, PACK_ID)).toBeNull();
  });

  it("descarta JSON inválido, null e formatos errados", () => {
    expect(parsePackRevealProgress(null, PACK_ID)).toBeNull();
    expect(parsePackRevealProgress("not-json", PACK_ID)).toBeNull();
    expect(parsePackRevealProgress(JSON.stringify({ foo: 1 }), PACK_ID)).toBeNull();
    expect(
      parsePackRevealProgress(
        JSON.stringify({ packId: PACK_ID, revealedCount: -1, stage: "revealing" }),
        PACK_ID,
      ),
    ).toBeNull();
  });
});

describe("getNextRevealState (máquina de estados)", () => {
  function revealingState(overrides: Partial<PackOpeningState> = {}): PackOpeningState {
    return {
      stage: "revealing",
      totalCards: 10,
      revealedCount: 0,
      phase: "hidden",
      error: null,
      ...overrides,
    };
  }

  it("começa em loading", () => {
    expect(createInitialPackOpeningState().stage).toBe("loading");
  });

  it("pacote fechado carregado vai para sealed", () => {
    const next = getNextRevealState(createInitialPackOpeningState(), {
      type: "EXPERIENCE_LOADED",
      opened: false,
      totalCards: 0,
    });
    expect(next.stage).toBe("sealed");
  });

  it("falha de carregamento vai para error", () => {
    const next = getNextRevealState(createInitialPackOpeningState(), {
      type: "LOAD_FAILED",
      message: "boom",
    });
    expect(next.stage).toBe("error");
    expect(next.error).toBe("boom");
  });

  it("pacote já aberto sem estado de sessão vai direto para already-opened", () => {
    const next = getNextRevealState(createInitialPackOpeningState(), {
      type: "EXPERIENCE_LOADED",
      opened: true,
      totalCards: 10,
    });
    expect(next.stage).toBe("already-opened");
    expect(next.revealedCount).toBe(10);
  });

  it("pacote aberto com progresso de sessão retoma a revelação", () => {
    const next = getNextRevealState(createInitialPackOpeningState(), {
      type: "EXPERIENCE_LOADED",
      opened: true,
      totalCards: 10,
      resume: { packId: PACK_ID, revealedCount: 4, stage: "revealing" },
    });
    expect(next.stage).toBe("revealing");
    expect(next.revealedCount).toBe(4);
    expect(next.phase).toBe("hidden");
  });

  it("pacote aberto com sessão em summary vai para summary", () => {
    const next = getNextRevealState(createInitialPackOpeningState(), {
      type: "EXPERIENCE_LOADED",
      opened: true,
      totalCards: 10,
      resume: { packId: PACK_ID, revealedCount: 10, stage: "summary" },
    });
    expect(next.stage).toBe("summary");
  });

  it("sealed + OPEN_REQUESTED vai para opening; segunda chamada não repete", () => {
    const sealed = getNextRevealState(createInitialPackOpeningState(), {
      type: "EXPERIENCE_LOADED",
      opened: false,
      totalCards: 0,
    });
    const opening = getNextRevealState(sealed, { type: "OPEN_REQUESTED" });
    expect(opening.stage).toBe("opening");
    expect(getNextRevealState(opening, { type: "OPEN_REQUESTED" })).toBe(opening);
  });

  it("erro na abertura volta para sealed e permite tentar de novo", () => {
    const opening: PackOpeningState = {
      stage: "opening",
      totalCards: 0,
      revealedCount: 0,
      phase: "hidden",
      error: null,
    };
    const failed = getNextRevealState(opening, { type: "OPEN_FAILED", message: "rls" });
    expect(failed.stage).toBe("sealed");
    expect(failed.error).toBe("rls");
    expect(getNextRevealState(failed, { type: "OPEN_REQUESTED" }).stage).toBe("opening");
  });

  it("abertura confirmada inicia a revelação zerada", () => {
    const opening: PackOpeningState = {
      stage: "opening",
      totalCards: 0,
      revealedCount: 0,
      phase: "hidden",
      error: null,
    };
    const next = getNextRevealState(opening, { type: "OPEN_SUCCEEDED", totalCards: 10 });
    expect(next).toMatchObject({
      stage: "revealing",
      totalCards: 10,
      revealedCount: 0,
      phase: "hidden",
    });
  });

  it("clique na carta oculta inicia a animação", () => {
    const next = getNextRevealState(revealingState(), { type: "CARD_CLICKED" });
    expect(next.phase).toBe("animating");
  });

  it("clique durante a animação não avança nada", () => {
    const animating = revealingState({ phase: "animating" });
    expect(getNextRevealState(animating, { type: "CARD_CLICKED" })).toBe(animating);
    expect(getNextRevealState(animating, { type: "CONTINUE_CLICKED" })).toBe(animating);
  });

  it("fim da animação revela a carta e incrementa o contador", () => {
    const next = getNextRevealState(revealingState({ phase: "animating" }), {
      type: "ANIMATION_FINISHED",
    });
    expect(next.phase).toBe("revealed");
    expect(next.revealedCount).toBe(1);
  });

  it("continuar após revelar volta para a próxima carta oculta", () => {
    const next = getNextRevealState(revealingState({ phase: "revealed", revealedCount: 3 }), {
      type: "CONTINUE_CLICKED",
    });
    expect(next.stage).toBe("revealing");
    expect(next.phase).toBe("hidden");
    expect(next.revealedCount).toBe(3);
  });

  it("continuar após a décima carta vai para summary", () => {
    const next = getNextRevealState(revealingState({ phase: "revealed", revealedCount: 10 }), {
      type: "CONTINUE_CLICKED",
    });
    expect(next.stage).toBe("summary");
  });

  it("pacote já aberto não aceita nova abertura", () => {
    const already: PackOpeningState = {
      stage: "already-opened",
      totalCards: 10,
      revealedCount: 10,
      phase: "revealed",
      error: null,
    };
    expect(getNextRevealState(already, { type: "OPEN_REQUESTED" })).toBe(already);

    const summary: PackOpeningState = { ...already, stage: "summary" };
    expect(getNextRevealState(summary, { type: "OPEN_REQUESTED" })).toBe(summary);
  });
});
