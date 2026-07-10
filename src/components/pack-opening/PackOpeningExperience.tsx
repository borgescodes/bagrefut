import { useCallback, useEffect, useMemo, useReducer, useRef } from "react";
import { useNavigate } from "@tanstack/react-router";
import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import { useServerFn } from "@tanstack/react-start";
import { getInitialPackExperience, openInitialPack } from "@/lib/pack.functions";
import type { InitialPackExperience, PackCard } from "@/lib/pack.functions";
import { PlayerCard } from "@/components/player-card";
import { playerImagePath } from "@/components/player-card/adapter";
import {
  createInitialPackOpeningState,
  getNextRevealState,
  getPackRevealStorageKey,
  parsePackRevealProgress,
  sortPackCardsForReveal,
} from "@/domain/pack-opening";
import type { PlayerRarity } from "@/domain/enums";
import "./pack-opening.css";

const REVEAL_DURATION_MS: Record<PlayerRarity, number> = {
  peba: 500,
  paia: 800,
  pika: 1300,
};

const REDUCED_MOTION_DURATION_MS = 180;

function prefersReducedMotion(): boolean {
  if (typeof window === "undefined") return false;
  return window.matchMedia("(prefers-reduced-motion: reduce)").matches;
}

function readSessionProgress(packId: string) {
  if (typeof window === "undefined") return null;
  try {
    return parsePackRevealProgress(
      window.sessionStorage.getItem(getPackRevealStorageKey(packId)),
      packId,
    );
  } catch {
    return null;
  }
}

function writeSessionProgress(
  packId: string,
  revealedCount: number,
  stage: "revealing" | "summary",
) {
  if (typeof window === "undefined") return;
  try {
    window.sessionStorage.setItem(
      getPackRevealStorageKey(packId),
      JSON.stringify({ packId, revealedCount, stage }),
    );
  } catch {
    // sessionStorage indisponível não pode quebrar a experiência.
  }
}

function preloadCardImages(cards: PackCard[]) {
  if (typeof window === "undefined") return;
  cards.forEach((card, index) => {
    try {
      const image = new Image();
      if (index === 0) image.fetchPriority = "high";
      image.decoding = "async";
      image.src = playerImagePath(card.player.id);
    } catch {
      // Sem asset para esta carta; o fallback visual cobre.
    }
  });
}

export function PackOpeningExperience() {
  const navigate = useNavigate();
  const queryClient = useQueryClient();
  const getExperienceFn = useServerFn(getInitialPackExperience);
  const openPackFn = useServerFn(openInitialPack);

  const [state, dispatch] = useReducer(getNextRevealState, undefined, () =>
    createInitialPackOpeningState(),
  );

  const experienceQuery = useQuery({
    queryKey: ["initialPackExperience"],
    queryFn: () => getExperienceFn(),
  });

  const experience = experienceQuery.data ?? null;
  const pack = experience?.pack ?? null;

  const sortedCards = useMemo(
    () => (experience ? sortPackCardsForReveal(experience.cards) : []),
    [experience],
  );

  // Sincroniza o carregamento inicial com a máquina de estados. A máquina
  // ignora EXPERIENCE_LOADED fora de loading/error, então refetches não
  // reiniciam a sequência.
  useEffect(() => {
    if (experienceQuery.isPending) return;
    if (experienceQuery.isError) {
      dispatch({
        type: "LOAD_FAILED",
        message:
          experienceQuery.error instanceof Error
            ? experienceQuery.error.message
            : "Falha ao carregar o pacote.",
      });
      return;
    }
    const loaded = experienceQuery.data;
    if (!loaded?.pack) return;
    dispatch({
      type: "EXPERIENCE_LOADED",
      opened: loaded.pack.openedAt !== null,
      totalCards: loaded.cards.length,
      resume: readSessionProgress(loaded.pack.id),
    });
  }, [
    experienceQuery.isPending,
    experienceQuery.isError,
    experienceQuery.data,
    experienceQuery.error,
  ]);

  const openMutation = useMutation({
    mutationFn: (clubId: string) => openPackFn({ data: { clubId } }),
    onSuccess: (result: InitialPackExperience) => {
      if (result.pack) {
        writeSessionProgress(result.pack.id, 0, "revealing");
      }
      queryClient.setQueryData(["initialPackExperience"], result);
      void queryClient.invalidateQueries({ queryKey: ["initialPackExperience"] });
      void queryClient.invalidateQueries({ queryKey: ["myRoster"] });
      void queryClient.invalidateQueries({ queryKey: ["marketWorkspace"] });
      dispatch({ type: "OPEN_SUCCEEDED", totalCards: result.cards.length });
    },
    onError: (error: unknown) => {
      dispatch({
        type: "OPEN_FAILED",
        message: error instanceof Error ? error.message : "Falha ao abrir o pacote.",
      });
    },
  });

  // Preload dos assets assim que as cartas existirem; nunca bloqueia o fluxo.
  const preloadedPackId = useRef<string | null>(null);
  useEffect(() => {
    if (!pack || sortedCards.length === 0) return;
    if (preloadedPackId.current === pack.id) return;
    preloadedPackId.current = pack.id;
    preloadCardImages(sortedCards);
  }, [pack, sortedCards]);

  // Fim da animação de revelação: controlado por timer, com duração por
  // raridade e atalho para prefers-reduced-motion.
  const currentCard: PackCard | null =
    state.stage === "revealing"
      ? (sortedCards[state.phase === "revealed" ? state.revealedCount - 1 : state.revealedCount] ??
        null)
      : null;

  useEffect(() => {
    if (state.stage !== "revealing" || state.phase !== "animating") return;
    const rarity = currentCard?.player.rarity ?? "peba";
    const duration = prefersReducedMotion()
      ? REDUCED_MOTION_DURATION_MS
      : REVEAL_DURATION_MS[rarity];
    const timer = window.setTimeout(() => dispatch({ type: "ANIMATION_FINISHED" }), duration);
    return () => window.clearTimeout(timer);
  }, [state.stage, state.phase, currentCard]);

  // Persiste o progresso da sessão (nunca o conteúdo das cartas).
  useEffect(() => {
    if (!pack) return;
    if (state.stage === "revealing") {
      writeSessionProgress(pack.id, state.revealedCount, "revealing");
    } else if (state.stage === "summary") {
      writeSessionProgress(pack.id, state.totalCards, "summary");
    }
  }, [pack, state.stage, state.revealedCount, state.totalCards]);

  const handleOpenClick = useCallback(() => {
    if (state.stage !== "sealed" || !pack || openMutation.isPending) return;
    dispatch({ type: "OPEN_REQUESTED" });
    openMutation.mutate(pack.clubId);
  }, [state.stage, pack, openMutation]);

  const handleRevealAreaActivate = useCallback(() => {
    if (state.stage !== "revealing") return;
    if (state.phase === "hidden") {
      dispatch({ type: "CARD_CLICKED" });
    } else if (state.phase === "revealed") {
      dispatch({ type: "CONTINUE_CLICKED" });
    }
  }, [state.stage, state.phase]);

  const handleRevealKeyDown = useCallback(
    (event: React.KeyboardEvent) => {
      if (event.key !== "Enter" && event.key !== " ") return;
      event.preventDefault();
      handleRevealAreaActivate();
    },
    [handleRevealAreaActivate],
  );

  if (experienceQuery.isSuccess && !pack) {
    return (
      <main className="pack-stage">
        <section className="pack-panel">
          <h1 className="pack-title">Abrir pacote inicial</h1>
          <p className="pack-hint">Você ainda não tem um pacote inicial disponível.</p>
          <button className="pack-action" onClick={() => navigate({ to: "/app" })}>
            Ir para início
          </button>
        </section>
      </main>
    );
  }

  return (
    <main className="pack-stage" data-stage={state.stage}>
      {state.stage === "loading" && (
        <section className="pack-panel" aria-busy="true">
          <div className="pack-loading-pulse" aria-hidden="true" />
          <p className="pack-hint">Carregando seu pacote…</p>
        </section>
      )}

      {state.stage === "error" && (
        <section className="pack-panel">
          <h1 className="pack-title">Algo deu errado</h1>
          <p className="pack-error" role="alert">
            {state.error}
          </p>
          <button className="pack-action" onClick={() => void experienceQuery.refetch()}>
            Tentar novamente
          </button>
        </section>
      )}

      {(state.stage === "sealed" || state.stage === "opening") && (
        <section className="pack-panel">
          <h1 className="pack-title">Seu pacote inicial chegou</h1>
          <p className="pack-hint">
            {state.stage === "opening"
              ? "Abrindo o pacote…"
              : "Toque no pacote para revelar suas 10 cartas."}
          </p>
          <button
            type="button"
            className="pack-artwork"
            data-opening={state.stage === "opening" || undefined}
            onClick={handleOpenClick}
            disabled={state.stage === "opening"}
            aria-label={state.stage === "opening" ? "Abrindo o pacote" : "Abrir pacote inicial"}
          >
            <span className="pack-body">
              <span className="pack-shine" aria-hidden="true" />
              <span className="pack-crest" aria-hidden="true">
                BAGRE
                <br />
                FUT
              </span>
              <span className="pack-label" aria-hidden="true">
                PACOTE INICIAL · 10 CARTAS
              </span>
            </span>
            <span className="pack-seal pack-seal--left" aria-hidden="true" />
            <span className="pack-seal pack-seal--right" aria-hidden="true" />
            <span className="pack-glow" aria-hidden="true" />
          </button>
          {state.error && (
            <p className="pack-error" role="alert">
              {state.error}
            </p>
          )}
        </section>
      )}

      {state.stage === "revealing" && currentCard && (
        <section className="pack-panel pack-panel--reveal">
          <p className="pack-counter" aria-live="polite">
            Carta {state.phase === "revealed" ? state.revealedCount : state.revealedCount + 1} de{" "}
            {state.totalCards}
            <span className="pack-counter__remaining">
              {state.totalCards -
                (state.phase === "revealed" ? state.revealedCount : state.revealedCount + 1)}{" "}
              restantes
            </span>
          </p>

          <div
            className="reveal-area"
            role="button"
            tabIndex={0}
            aria-busy={state.phase === "animating"}
            aria-label={
              state.phase === "hidden"
                ? "Revelar próxima carta"
                : state.phase === "animating"
                  ? "Revelando carta"
                  : state.revealedCount >= state.totalCards
                    ? "Ver resumo das cartas"
                    : "Próxima carta"
            }
            data-phase={state.phase}
            data-rarity={currentCard.player.rarity}
            onClick={handleRevealAreaActivate}
            onKeyDown={handleRevealKeyDown}
            style={
              {
                "--reveal-duration": `${REVEAL_DURATION_MS[currentCard.player.rarity]}ms`,
              } as React.CSSProperties
            }
          >
            <div className="reveal-dim" aria-hidden="true" />
            <div className="reveal-burst" aria-hidden="true">
              {Array.from({ length: 12 }, (_, index) => (
                <span key={index} className="reveal-particle" />
              ))}
              <span className="reveal-flash" />
              <span className="reveal-rays" />
            </div>

            <div className="reveal-flip">
              <div className="reveal-flip__back" aria-hidden={state.phase === "revealed"}>
                <span className="reveal-back-mark">BAGREFUT</span>
                <span className="reveal-back-sub">TOQUE PARA REVELAR</span>
              </div>
              <div className="reveal-flip__front" aria-hidden={state.phase !== "revealed"}>
                {state.phase === "revealed" && (
                  <PlayerCard player={currentCard.player} priority className="reveal-card" />
                )}
              </div>
            </div>
          </div>

          <p className="pack-hint" aria-live="polite">
            {state.phase === "hidden" && "Toque na carta para revelar."}
            {state.phase === "animating" && "…"}
            {state.phase === "revealed" &&
              (state.revealedCount >= state.totalCards
                ? "Toque para ver o resumo."
                : "Toque para a próxima carta.")}
          </p>
        </section>
      )}

      {(state.stage === "summary" || state.stage === "already-opened") && (
        <section className="pack-panel pack-panel--summary">
          <h1 className="pack-title">Cartas adquiridas</h1>
          <ul className="summary-grid">
            {sortedCards.map((card) => (
              <li key={card.slot} className="summary-grid__item">
                <PlayerCard player={card.player} />
              </li>
            ))}
          </ul>
          <div className="summary-actions">
            <button className="pack-action" onClick={() => navigate({ to: "/elenco" })}>
              Ver elenco
            </button>
            <button
              className="pack-action pack-action--ghost"
              onClick={() => navigate({ to: "/app" })}
            >
              Ir para início
            </button>
          </div>
        </section>
      )}
    </main>
  );
}
