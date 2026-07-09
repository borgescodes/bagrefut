import { Link, createFileRoute } from "@tanstack/react-router";
import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import { useServerFn } from "@tanstack/react-start";
import {
  useEffect,
  useMemo,
  useState,
  type Dispatch,
  type ReactNode,
  type SetStateAction,
} from "react";
import { FORMATIONS, PLAY_STYLES, type Formation, type PlayStyle } from "@/domain/enums";
import {
  buildInitialLineupDraft,
  canSubmitLineup,
  getAttributeEntries,
  getEffectiveOverall,
  getFormationSlots,
  getImprovisationPenalty,
  getLineupSourceNotice,
  hydrateLineupDraft,
  isImprovised,
  validateLineupDraft,
  type FormationSlot,
  type LineupDraft,
  type LineupRosterPlayer,
  type LineupSlotKey,
} from "@/domain/lineup";
import {
  getLineupWorkspace,
  mapSaveLineupErrorMessage,
  saveLineup as saveLineupServer,
} from "@/lib/lineup.functions";

export const Route = createFileRoute("/_authenticated/elenco")({
  component: RosterLineupPage,
});

const EMPTY_ROSTER: LineupRosterPlayer[] = [];

function RosterLineupPage() {
  const workspaceFn = useServerFn(getLineupWorkspace);
  const saveFn = useServerFn(saveLineupServer);
  const queryClient = useQueryClient();
  const [draft, setDraft] = useState<LineupDraft>(() => buildInitialLineupDraft());
  const [loadedKey, setLoadedKey] = useState<string | null>(null);
  const [selectedPlayerId, setSelectedPlayerId] = useState<string | null>(null);
  const [saveMessage, setSaveMessage] = useState<string | null>(null);
  const [saveError, setSaveError] = useState<string | null>(null);

  const workspace = useQuery({
    queryKey: ["lineupWorkspace"],
    queryFn: () => workspaceFn(),
    refetchInterval: 60_000,
  });

  const workspaceKey = useMemo(() => {
    if (!workspace.data) return null;
    return JSON.stringify({
      roundId: workspace.data.round?.id ?? null,
      savedLineup: workspace.data.savedLineup,
    });
  }, [workspace.data]);

  useEffect(() => {
    if (!workspace.data || !workspaceKey || workspaceKey === loadedKey) return;
    setDraft(hydrateLineupDraft(workspace.data.savedLineup));
    setLoadedKey(workspaceKey);
    setSaveMessage(null);
    setSaveError(null);
  }, [loadedKey, workspace.data, workspaceKey]);

  const roster = workspace.data?.roster ?? EMPTY_ROSTER;
  const validation = useMemo(() => validateLineupDraft(draft, roster), [draft, roster]);
  const selectedPlayer = roster.find((player) => player.clubPlayerId === selectedPlayerId) ?? null;

  const saveMutation = useMutation({
    mutationFn: async () => {
      if (!isPlayStyle(draft.style)) {
        throw new Error("Estilo de jogo invalido.");
      }
      if (!validation.valid) {
        throw new Error(validation.errors[0] ?? "Escalacao invalida.");
      }
      return saveFn({
        data: {
          formation: draft.formation,
          style: draft.style,
          players: validation.players,
        },
      });
    },
    onSuccess: async () => {
      setSaveMessage("Escalacao salva com sucesso.");
      setSaveError(null);
      await queryClient.invalidateQueries({ queryKey: ["lineupWorkspace"] });
    },
    onError: (error) => {
      setSaveMessage(null);
      setSaveError(mapSaveLineupErrorMessage(error));
    },
  });

  const submitState = canSubmitLineup({
    validation,
    isSaving: saveMutation.isPending,
    isBlocked: workspace.data?.round?.isBlocked ?? false,
  });

  if (workspace.isLoading) {
    return (
      <Shell title="Elenco e escalacao">
        <p className="text-sm text-slate-400">Carregando elenco...</p>
      </Shell>
    );
  }

  if (workspace.error) {
    return (
      <Shell title="Elenco e escalacao">
        <p className="text-sm text-red-400">Erro ao carregar elenco.</p>
      </Shell>
    );
  }

  if (!workspace.data?.club) {
    return (
      <Shell title="Elenco e escalacao">
        <p className="text-sm text-slate-300">Voce ainda nao tem clube.</p>
        <Link
          to="/criar-clube"
          className="mt-4 inline-flex rounded-md bg-slate-100 px-3 py-2 text-sm text-slate-950"
        >
          Criar clube
        </Link>
      </Shell>
    );
  }

  return (
    <Shell title="Elenco e escalacao">
      <div className="mb-5 flex flex-wrap items-center justify-between gap-3">
        <div>
          <p className="text-sm text-slate-400">Clube</p>
          <p className="font-medium">
            {workspace.data.club.name} ({workspace.data.club.abbreviation})
          </p>
        </div>
        <Link to="/app" className="text-sm underline">
          Voltar
        </Link>
      </div>

      <RoundStatus round={workspace.data.round} />

      {!workspace.data.round && (
        <p className="mt-4 rounded-md border border-slate-800 p-3 text-sm text-slate-300">
          Nao ha rodada ativa disponivel para salvar escalacao agora.
        </p>
      )}

      <p className="mt-4 rounded-md border border-slate-800 p-3 text-sm text-slate-300">
        {getLineupSourceNotice(workspace.data.savedLineup)}
      </p>

      {roster.length === 0 ? (
        <p className="mt-6 text-sm text-slate-400">Seu clube ainda nao tem jogadores.</p>
      ) : (
        <div className="mt-6 grid gap-6 lg:grid-cols-[minmax(0,1fr)_minmax(320px,420px)]">
          <section>
            <h2 className="text-lg font-semibold">Elenco</h2>
            <div className="mt-3 grid gap-3 sm:grid-cols-2">
              {roster.map((player) => (
                <PlayerCard
                  key={player.clubPlayerId}
                  player={player}
                  draft={draft}
                  selected={player.clubPlayerId === selectedPlayerId}
                  onSelect={() => setSelectedPlayerId(player.clubPlayerId)}
                />
              ))}
            </div>
          </section>

          <aside className="space-y-4">
            <LineupEditor
              draft={draft}
              roster={roster}
              setDraft={setDraft}
              validation={validation}
            />

            <section className="rounded-md border border-slate-800 p-4">
              <h2 className="text-base font-semibold">Salvar</h2>
              <div className="mt-3 space-y-2 text-sm">
                {validation.valid ? (
                  <p className="text-emerald-300">Escalacao valida.</p>
                ) : (
                  <div className="text-amber-300">
                    <p>Escalacao incompleta ou invalida.</p>
                    <ul className="mt-1 list-disc space-y-1 pl-5">
                      {validation.errors.map((error) => (
                        <li key={error}>{error}</li>
                      ))}
                    </ul>
                  </div>
                )}
                {submitState.reason && (
                  <p className="text-slate-400">Estado: {submitState.reason}</p>
                )}
                {saveMessage && <p className="text-emerald-300">{saveMessage}</p>}
                {saveError && <p className="text-red-300">{saveError}</p>}
              </div>
              <button
                type="button"
                disabled={!submitState.canSubmit || !workspace.data.round}
                onClick={() => saveMutation.mutate()}
                className="mt-4 w-full rounded-md bg-slate-100 px-4 py-2 text-sm font-medium text-slate-950 focus-visible:outline focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-slate-100 disabled:cursor-not-allowed disabled:opacity-60"
              >
                {saveMutation.isPending ? "Salvando..." : "Salvar escalacao"}
              </button>
            </section>

            <PlayerDetails player={selectedPlayer} draft={draft} />
          </aside>
        </div>
      )}
    </Shell>
  );
}

function LineupEditor({
  draft,
  roster,
  setDraft,
  validation,
}: {
  draft: LineupDraft;
  roster: LineupRosterPlayer[];
  setDraft: Dispatch<SetStateAction<LineupDraft>>;
  validation: ReturnType<typeof validateLineupDraft>;
}) {
  const slots = getFormationSlots(draft.formation);

  return (
    <section className="rounded-md border border-slate-800 p-4">
      <h2 className="text-base font-semibold">Montagem</h2>

      <div className="mt-4 grid gap-3 sm:grid-cols-2">
        <label className="text-sm">
          <span className="block text-slate-300">Formacao</span>
          <select
            value={draft.formation}
            onChange={(event) => {
              const formation = parseFormation(event.target.value);
              setDraft((current) => moveFormation(current, formation));
            }}
            className="mt-1 w-full rounded-md border border-slate-700 bg-slate-950 px-3 py-2 text-sm"
          >
            {FORMATIONS.map((formation) => (
              <option key={formation} value={formation}>
                {formation}
              </option>
            ))}
          </select>
        </label>

        <label className="text-sm">
          <span className="block text-slate-300">Estilo</span>
          <select
            value={draft.style}
            onChange={(event) =>
              setDraft((current) => ({ ...current, style: parsePlayStyle(event.target.value) }))
            }
            className="mt-1 w-full rounded-md border border-slate-700 bg-slate-950 px-3 py-2 text-sm"
          >
            {PLAY_STYLES.map((style) => (
              <option key={style} value={style}>
                {style}
              </option>
            ))}
          </select>
        </label>
      </div>

      <div className="mt-5 space-y-3">
        <h3 className="text-sm font-medium text-slate-300">Titulares</h3>
        {slots.map((slot) => (
          <StarterSlot
            key={slot.key}
            slot={slot}
            draft={draft}
            roster={roster}
            setDraft={setDraft}
          />
        ))}
      </div>

      <div className="mt-5 space-y-3">
        <div className="flex items-center justify-between gap-3">
          <h3 className="text-sm font-medium text-slate-300">Reservas</h3>
          <button
            type="button"
            disabled={draft.reserves.length >= 5}
            onClick={() =>
              setDraft((current) => ({ ...current, reserves: [...current.reserves, ""] }))
            }
            className="rounded-md border border-slate-700 px-2 py-1 text-xs disabled:opacity-50"
          >
            Adicionar reserva
          </button>
        </div>
        {draft.reserves.length === 0 ? (
          <p className="text-sm text-slate-500">Nenhum reserva selecionado.</p>
        ) : (
          draft.reserves.map((clubPlayerId, index) => (
            <ReserveSlot
              key={`${index}-${clubPlayerId}`}
              index={index}
              clubPlayerId={clubPlayerId}
              draft={draft}
              roster={roster}
              setDraft={setDraft}
            />
          ))
        )}
      </div>

      {validation.players.length > 0 && (
        <p className="mt-4 text-xs text-slate-500">
          {validation.players.filter((player) => player.isStarter).length} titulares /{" "}
          {validation.players.filter((player) => !player.isStarter).length} reservas
        </p>
      )}
    </section>
  );
}

function StarterSlot({
  slot,
  draft,
  roster,
  setDraft,
}: {
  slot: FormationSlot;
  draft: LineupDraft;
  roster: LineupRosterPlayer[];
  setDraft: Dispatch<SetStateAction<LineupDraft>>;
}) {
  const clubPlayerId = draft.starters[slot.key] ?? "";
  const player = roster.find((item) => item.clubPlayerId === clubPlayerId) ?? null;

  return (
    <div className="rounded-md border border-slate-900 p-3">
      <label className="text-sm">
        <span className="block text-slate-300">{slot.label}</span>
        <select
          value={clubPlayerId}
          onChange={(event) => {
            const nextPlayerId = event.target.value;
            setDraft((current) => assignStarter(current, slot, nextPlayerId));
          }}
          className="mt-1 w-full rounded-md border border-slate-700 bg-slate-950 px-3 py-2 text-sm"
        >
          <option value="">Selecionar jogador</option>
          {roster.map((option) => (
            <option key={option.clubPlayerId} value={option.clubPlayerId}>
              {option.name} - {option.position} - OVR {option.overall}
            </option>
          ))}
        </select>
      </label>
      {player && (
        <div className="mt-2 text-xs text-slate-400">
          <p>OVR base: {player.overall}</p>
          <p>OVR efetivo: {getEffectiveOverall(player, slot.position)}</p>
          {isImprovised(player, slot.position) ? (
            <p className="text-amber-300">
              Improvisado: {player.position} em {slot.position} (-
              {Math.round(getImprovisationPenalty(player, slot.position) * 100)}%)
            </p>
          ) : (
            <p className="text-emerald-300">Posicao principal.</p>
          )}
        </div>
      )}
      {clubPlayerId && (
        <button
          type="button"
          onClick={() => setDraft((current) => assignStarter(current, slot, ""))}
          className="mt-2 rounded-md border border-slate-700 px-2 py-1 text-xs"
        >
          Remover
        </button>
      )}
    </div>
  );
}

function ReserveSlot({
  index,
  clubPlayerId,
  draft,
  roster,
  setDraft,
}: {
  index: number;
  clubPlayerId: string;
  draft: LineupDraft;
  roster: LineupRosterPlayer[];
  setDraft: Dispatch<SetStateAction<LineupDraft>>;
}) {
  const player = roster.find((item) => item.clubPlayerId === clubPlayerId) ?? null;
  return (
    <div className="rounded-md border border-slate-900 p-3">
      <label className="text-sm">
        <span className="block text-slate-300">Reserva {index + 1}</span>
        <select
          value={clubPlayerId}
          onChange={(event) => {
            const nextPlayerId = event.target.value;
            setDraft((current) => assignReserve(current, index, nextPlayerId));
          }}
          className="mt-1 w-full rounded-md border border-slate-700 bg-slate-950 px-3 py-2 text-sm"
        >
          <option value="">Selecionar reserva</option>
          {roster.map((option) => (
            <option key={option.clubPlayerId} value={option.clubPlayerId}>
              {option.name} - {option.position} - OVR {option.overall}
            </option>
          ))}
        </select>
      </label>
      {player && <p className="mt-2 text-xs text-slate-400">OVR base: {player.overall}</p>}
      <button
        type="button"
        onClick={() => setDraft((current) => removeReserveAt(current, index))}
        className="mt-2 rounded-md border border-slate-700 px-2 py-1 text-xs"
      >
        Remover reserva
      </button>
    </div>
  );
}

function PlayerCard({
  player,
  draft,
  selected,
  onSelect,
}: {
  player: LineupRosterPlayer;
  draft: LineupDraft;
  selected: boolean;
  onSelect: () => void;
}) {
  const slot = findStarterSlot(draft, player.clubPlayerId);
  const isReserve = draft.reserves.includes(player.clubPlayerId);
  const state = slot ? "titular" : isReserve ? "reserva" : "fora da escalacao";
  const improvised = slot ? isImprovised(player, slot.position) : false;

  return (
    <button
      type="button"
      onClick={onSelect}
      className={`rounded-md border p-3 text-left focus-visible:outline focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-slate-100 ${
        selected ? "border-slate-100" : "border-slate-800"
      }`}
    >
      <div className="flex items-start justify-between gap-3">
        <div>
          <h3 className="font-medium">{player.name}</h3>
          <p className="text-xs text-slate-400">
            {player.position} - OVR {player.overall}
          </p>
        </div>
        <span className="rounded-sm border border-slate-700 px-2 py-1 text-xs">{state}</span>
      </div>
      {slot && (
        <p className="mt-2 text-xs text-slate-400">
          Posicao escolhida: {slot.label}. OVR efetivo: {getEffectiveOverall(player, slot.position)}
        </p>
      )}
      {improvised && <p className="mt-1 text-xs text-amber-300">Improvisado</p>}
      <dl className="mt-3 grid grid-cols-2 gap-1 text-xs text-slate-400">
        {getAttributeEntries(player).map((attribute) => (
          <div key={attribute.key} className="flex justify-between gap-2">
            <dt>{attribute.key}</dt>
            <dd>{attribute.value}</dd>
          </div>
        ))}
      </dl>
    </button>
  );
}

function PlayerDetails({
  player,
  draft,
}: {
  player: LineupRosterPlayer | null;
  draft: LineupDraft;
}) {
  if (!player) {
    return (
      <section className="rounded-md border border-slate-800 p-4">
        <h2 className="text-base font-semibold">Detalhes do jogador</h2>
        <p className="mt-2 text-sm text-slate-400">Selecione um jogador do elenco.</p>
      </section>
    );
  }

  const slot = findStarterSlot(draft, player.clubPlayerId);
  const isReserve = draft.reserves.includes(player.clubPlayerId);
  const chosenPosition = slot?.position ?? null;

  return (
    <section className="rounded-md border border-slate-800 p-4">
      <h2 className="text-base font-semibold">Detalhes do jogador</h2>
      <div className="mt-3 space-y-2 text-sm">
        <p>
          <b>{player.name}</b>
        </p>
        <p>Posicao principal: {player.position}</p>
        <p>OVR base: {player.overall}</p>
        <p>Estado: {slot ? "titular" : isReserve ? "reserva" : "fora da escalacao"}</p>
        <p>Posicao escolhida: {chosenPosition ?? "nenhuma"}</p>
        {chosenPosition ? (
          <p>
            Impacto de improviso:{" "}
            {isImprovised(player, chosenPosition)
              ? `-${Math.round(
                  getImprovisationPenalty(player, chosenPosition) * 100,
                )}%, OVR efetivo ${getEffectiveOverall(player, chosenPosition)}`
              : `sem penalidade, OVR efetivo ${getEffectiveOverall(player, chosenPosition)}`}
          </p>
        ) : (
          <p>Impacto de improviso: nao aplicavel.</p>
        )}
      </div>
      <div className="mt-4">
        <h3 className="text-sm font-medium text-slate-300">Atributos</h3>
        <dl className="mt-2 grid grid-cols-2 gap-2 text-sm text-slate-400">
          {getAttributeEntries(player).map((attribute) => (
            <div key={attribute.key} className="flex justify-between gap-3">
              <dt>{attribute.key}</dt>
              <dd>{attribute.value}</dd>
            </div>
          ))}
        </dl>
      </div>
      <div className="mt-4">
        <h3 className="text-sm font-medium text-slate-300">Treino / evolucao</h3>
        {player.attributeProgress?.length ? (
          <ul className="mt-2 space-y-1 text-sm text-slate-400">
            {player.attributeProgress.map((progress) => (
              <li key={progress.attribute}>
                {progress.attribute}: {progress.progress}%
              </li>
            ))}
          </ul>
        ) : (
          <p className="mt-2 text-sm text-slate-500">Sem progresso registrado.</p>
        )}
      </div>
    </section>
  );
}

function RoundStatus({
  round,
}: {
  round: {
    roundNumber: number;
    lineupLockAt: string;
    startsAt: string;
    isBlocked: boolean;
  } | null;
}) {
  if (!round) return null;
  return (
    <section className="rounded-md border border-slate-800 p-4 text-sm">
      <h2 className="font-semibold">Rodada {round.roundNumber}</h2>
      <p className="mt-1 text-slate-400">Inicio: {formatDateTime(round.startsAt)}</p>
      <p className="text-slate-400">Limite de escalacao: {formatDateTime(round.lineupLockAt)}</p>
      <p className={round.isBlocked ? "mt-2 text-red-300" : "mt-2 text-emerald-300"}>
        {round.isBlocked
          ? "Escalacao bloqueada pelo horario limite."
          : "Escalacao aberta para edicao."}
      </p>
    </section>
  );
}

function Shell({ title, children }: { title: string; children: ReactNode }) {
  return (
    <main className="min-h-screen bg-[#0b0f14] px-4 py-8 text-slate-100 sm:px-6">
      <div className="mx-auto max-w-6xl">
        <h1 className="text-xl font-bold">{title}</h1>
        <div className="mt-6">{children}</div>
      </div>
    </main>
  );
}

function assignStarter(draft: LineupDraft, slot: FormationSlot, clubPlayerId: string): LineupDraft {
  const next = removePlayerFromDraft(cloneDraft(draft), clubPlayerId);
  if (clubPlayerId) {
    next.starters[slot.key] = clubPlayerId;
  } else {
    delete next.starters[slot.key];
  }
  return next;
}

function assignReserve(draft: LineupDraft, index: number, clubPlayerId: string): LineupDraft {
  const next = removePlayerFromDraft(cloneDraft(draft), clubPlayerId);
  next.reserves[index] = clubPlayerId;
  return next;
}

function removeReserveAt(draft: LineupDraft, index: number): LineupDraft {
  const next = cloneDraft(draft);
  next.reserves.splice(index, 1);
  return next;
}

function removePlayerFromDraft(draft: LineupDraft, clubPlayerId: string): LineupDraft {
  if (!clubPlayerId) return draft;
  for (const key of Object.keys(draft.starters) as LineupSlotKey[]) {
    if (draft.starters[key] === clubPlayerId) {
      delete draft.starters[key];
    }
  }
  draft.reserves = draft.reserves.filter((reserveId) => reserveId !== clubPlayerId);
  return draft;
}

function moveFormation(draft: LineupDraft, formation: Formation): LineupDraft {
  const allowedSlots = new Set(getFormationSlots(formation).map((slot) => slot.key));
  const starters: Partial<Record<LineupSlotKey, string>> = {};
  for (const [key, clubPlayerId] of Object.entries(draft.starters) as Array<
    [LineupSlotKey, string]
  >) {
    if (allowedSlots.has(key)) {
      starters[key] = clubPlayerId;
    }
  }
  return { ...draft, formation, starters };
}

function cloneDraft(draft: LineupDraft): LineupDraft {
  return {
    formation: draft.formation,
    style: draft.style,
    starters: { ...draft.starters },
    reserves: [...draft.reserves],
  };
}

function findStarterSlot(draft: LineupDraft, clubPlayerId: string): FormationSlot | null {
  return (
    getFormationSlots(draft.formation).find((slot) => draft.starters[slot.key] === clubPlayerId) ??
    null
  );
}

function parseFormation(value: string): Formation {
  return FORMATIONS.find((formation) => formation === value) ?? FORMATIONS[0];
}

function parsePlayStyle(value: string): PlayStyle {
  return PLAY_STYLES.find((style) => style === value) ?? "balanced";
}

function isPlayStyle(value: string): value is PlayStyle {
  return PLAY_STYLES.some((style) => style === value);
}

function formatDateTime(value: string): string {
  return new Intl.DateTimeFormat("pt-BR", {
    dateStyle: "short",
    timeStyle: "short",
  }).format(new Date(value));
}
