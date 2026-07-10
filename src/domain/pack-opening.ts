import { z } from "zod";
import type { PlayerRarity } from "@/domain/enums";

/**
 * Domínio puro da sequência de revelação do pacote inicial.
 * Nada aqui altera sorteio, slots persistidos ou banco — apenas apresentação.
 */

export type PackOpeningStage =
  | "loading"
  | "sealed"
  | "opening"
  | "revealing"
  | "summary"
  | "already-opened"
  | "error";

export type RevealPhase = "hidden" | "animating" | "revealed";

export type PackOpeningState = {
  stage: PackOpeningStage;
  totalCards: number;
  /** Cartas já reveladas por completo. */
  revealedCount: number;
  /** Fase da carta atual enquanto stage === "revealing". */
  phase: RevealPhase;
  error: string | null;
};

export const packRevealProgressSchema = z.object({
  packId: z.string().uuid(),
  revealedCount: z.number().int().min(0),
  stage: z.enum(["revealing", "summary"]),
});

export type PackRevealProgress = z.infer<typeof packRevealProgressSchema>;

export type PackOpeningEvent =
  | {
      type: "EXPERIENCE_LOADED";
      opened: boolean;
      totalCards: number;
      resume?: PackRevealProgress | null;
    }
  | { type: "LOAD_FAILED"; message: string }
  | { type: "OPEN_REQUESTED" }
  | { type: "OPEN_SUCCEEDED"; totalCards: number }
  | { type: "OPEN_FAILED"; message: string }
  | { type: "CARD_CLICKED" }
  | { type: "ANIMATION_FINISHED" }
  | { type: "CONTINUE_CLICKED" };

const RARITY_REVEAL_ORDER = ["peba", "paia", "pika"] as const satisfies readonly PlayerRarity[];

/** peba = 0, paia = 1, pika = 2 — usado só para ordenar a apresentação. */
export function rarityRevealRank(rarity: PlayerRarity): number {
  return RARITY_REVEAL_ORDER.indexOf(rarity);
}

type RevealSortable = {
  slot: number;
  player: { overall: number; rarity: PlayerRarity };
};

/**
 * Ordem de apresentação: overall crescente, depois raridade crescente
 * (peba < paia < pika), depois slot crescente para desempate estável.
 * Não muta a entrada. A maior carta fica sempre por último.
 */
export function sortPackCardsForReveal<T extends RevealSortable>(cards: readonly T[]): T[] {
  return [...cards].sort(
    (a, b) =>
      a.player.overall - b.player.overall ||
      rarityRevealRank(a.player.rarity) - rarityRevealRank(b.player.rarity) ||
      a.slot - b.slot,
  );
}

/** Chave de sessionStorage do progresso de revelação, escopada por pack.id. */
export function getPackRevealStorageKey(packId: string): string {
  return `bagrefut:pack-reveal:${packId}`;
}

/**
 * Decodifica progresso salvo em sessionStorage. Retorna null para JSON
 * inválido, formato errado ou progresso de outro pacote.
 */
export function parsePackRevealProgress(
  raw: string | null,
  packId: string,
): PackRevealProgress | null {
  if (!raw) return null;
  let parsed: unknown;
  try {
    parsed = JSON.parse(raw);
  } catch {
    return null;
  }
  const result = packRevealProgressSchema.safeParse(parsed);
  if (!result.success) return null;
  if (result.data.packId !== packId) return null;
  return result.data;
}

export function createInitialPackOpeningState(): PackOpeningState {
  return { stage: "loading", totalCards: 0, revealedCount: 0, phase: "hidden", error: null };
}

/**
 * Máquina de estados da abertura. Transições inválidas devolvem o mesmo
 * objeto de estado — isso bloqueia abertura dupla, clique duplo durante
 * animação, avanço de duas cartas e nova mutação após pacote aberto.
 */
export function getNextRevealState(
  state: PackOpeningState,
  event: PackOpeningEvent,
): PackOpeningState {
  switch (event.type) {
    case "EXPERIENCE_LOADED": {
      if (state.stage !== "loading" && state.stage !== "error") return state;
      if (!event.opened) {
        return { ...state, stage: "sealed", totalCards: 0, revealedCount: 0, error: null };
      }
      const resume = event.resume ?? null;
      if (resume && resume.stage === "revealing" && resume.revealedCount < event.totalCards) {
        return {
          stage: "revealing",
          totalCards: event.totalCards,
          revealedCount: resume.revealedCount,
          phase: "hidden",
          error: null,
        };
      }
      if (resume && resume.stage === "summary") {
        return {
          stage: "summary",
          totalCards: event.totalCards,
          revealedCount: event.totalCards,
          phase: "revealed",
          error: null,
        };
      }
      return {
        stage: "already-opened",
        totalCards: event.totalCards,
        revealedCount: event.totalCards,
        phase: "revealed",
        error: null,
      };
    }

    case "LOAD_FAILED":
      if (state.stage !== "loading") return state;
      return { ...state, stage: "error", error: event.message };

    case "OPEN_REQUESTED":
      if (state.stage !== "sealed") return state;
      return { ...state, stage: "opening", error: null };

    case "OPEN_SUCCEEDED":
      if (state.stage !== "opening") return state;
      return {
        stage: "revealing",
        totalCards: event.totalCards,
        revealedCount: 0,
        phase: "hidden",
        error: null,
      };

    case "OPEN_FAILED":
      if (state.stage !== "opening") return state;
      return { ...state, stage: "sealed", error: event.message };

    case "CARD_CLICKED":
      if (state.stage !== "revealing" || state.phase !== "hidden") return state;
      return { ...state, phase: "animating" };

    case "ANIMATION_FINISHED":
      if (state.stage !== "revealing" || state.phase !== "animating") return state;
      return { ...state, phase: "revealed", revealedCount: state.revealedCount + 1 };

    case "CONTINUE_CLICKED": {
      if (state.stage !== "revealing" || state.phase !== "revealed") return state;
      if (state.revealedCount >= state.totalCards) {
        return { ...state, stage: "summary" };
      }
      return { ...state, phase: "hidden" };
    }

    default:
      return state;
  }
}
