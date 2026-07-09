import { createFileRoute, Link } from "@tanstack/react-router";
import { useQuery } from "@tanstack/react-query";
import { useServerFn } from "@tanstack/react-start";
import {
  adaptSeasonRpcState,
  formatStandingsRow,
  type SeasonOperationalStatus,
  type SeasonRpcState,
} from "@/domain/season";
import {
  getSeasonHistory,
  getSeasonOperationalState,
  getSeasonStandings,
} from "@/lib/season.functions";

export const Route = createFileRoute("/_authenticated/classificacao")({
  component: StandingsPage,
});

function StandingsPage() {
  const stateFn = useServerFn(getSeasonOperationalState);
  const standingsFn = useServerFn(getSeasonStandings);
  const historyFn = useServerFn(getSeasonHistory);

  const state = useQuery({ queryKey: ["season", "state"], queryFn: () => stateFn() });
  const standings = useQuery({ queryKey: ["season", "standings"], queryFn: () => standingsFn() });
  const history = useQuery({ queryKey: ["season", "history"], queryFn: () => historyFn() });

  const uiState = state.data ? adaptSeasonRpcState(asSeasonRpcState(state.data)) : null;
  const currentRound = state.data ? readRecord(asRecord(state.data).current_round) : null;
  const activeSeason = state.data ? readRecord(asRecord(state.data).active_season) : null;
  const historyRows = Array.isArray(history.data)
    ? history.data.map(readRecord).filter((row): row is Record<string, unknown> => row !== null)
    : [];

  return (
    <main className="min-h-screen bg-[#0b0f14] px-4 py-8 text-slate-100 sm:px-6">
      <div className="mx-auto max-w-5xl">
        <Link to="/app" className="text-sm underline">
          Voltar
        </Link>
        <h1 className="mt-4 text-xl font-bold">Classificacao</h1>

        <section className="mt-6 rounded-md border border-slate-800 p-4">
          <h2 className="font-medium">Temporada atual</h2>
          {state.isLoading ? (
            <p className="mt-2 text-sm text-slate-400">Carregando...</p>
          ) : state.error || !uiState ? (
            <p className="mt-2 text-sm text-red-400">Nao foi possivel carregar a temporada.</p>
          ) : (
            <div className="mt-3 grid gap-3 text-sm sm:grid-cols-3">
              <Info label="Status" value={statusLabel(uiState.operationalStatus)} />
              <Info label="Clubes" value={`${uiState.eligibleCount} de ${uiState.requiredCount}`} />
              <Info label="Faltam" value={String(uiState.missingCount)} />
              {activeSeason && (
                <Info label="Temporada" value={String(activeSeason.name ?? "Temporada ativa")} />
              )}
              {currentRound && (
                <Info
                  label="Rodada atual"
                  value={`Rodada ${String(currentRound.round_number ?? "-")}`}
                />
              )}
              {currentRound && (
                <Info
                  label="Partidas concluidas"
                  value={`${String(currentRound.completed_matches ?? 0)} de ${String(
                    currentRound.match_count ?? 0,
                  )}`}
                />
              )}
            </div>
          )}
          {uiState?.operationalStatus === "waiting_for_clubs" && (
            <p className="mt-4 rounded-md border border-amber-700 bg-amber-950/30 p-3 text-sm text-amber-100">
              {uiState.waitingMessage}
            </p>
          )}
        </section>

        <section className="mt-6 rounded-md border border-slate-800 p-4">
          <h2 className="font-medium">Tabela</h2>
          {standings.isLoading ? (
            <p className="mt-2 text-sm text-slate-400">Carregando classificacao...</p>
          ) : standings.error ? (
            <p className="mt-2 text-sm text-red-400">Nao foi possivel carregar a classificacao.</p>
          ) : standings.data?.standings.length ? (
            <div className="mt-4 overflow-x-auto">
              <table className="min-w-[760px] w-full text-sm">
                <thead className="border-b border-slate-800 text-left text-xs uppercase text-slate-500">
                  <tr>
                    <th className="py-2">Pos</th>
                    <th>Clube</th>
                    <th>J</th>
                    <th>Pts</th>
                    <th>V</th>
                    <th>E</th>
                    <th>D</th>
                    <th>GP</th>
                    <th>GC</th>
                    <th>SG</th>
                  </tr>
                </thead>
                <tbody>
                  {standings.data.standings.map((row) => {
                    const formatted = formatStandingsRow(row);
                    return (
                      <tr key={row.club_id} className="border-b border-slate-900">
                        <td className="py-2">{formatted.position}</td>
                        <td>{formatted.club}</td>
                        <td>{formatted.played}</td>
                        <td>{formatted.points}</td>
                        <td>{formatted.wins}</td>
                        <td>{formatted.draws}</td>
                        <td>{formatted.losses}</td>
                        <td>{formatted.goalsFor}</td>
                        <td>{formatted.goalsAgainst}</td>
                        <td>{formatted.goalDifference}</td>
                      </tr>
                    );
                  })}
                </tbody>
              </table>
            </div>
          ) : (
            <p className="mt-2 text-sm text-slate-400">Classificacao indisponivel.</p>
          )}
        </section>

        <section className="mt-6 rounded-md border border-slate-800 p-4">
          <h2 className="font-medium">Historico</h2>
          {history.isLoading ? (
            <p className="mt-2 text-sm text-slate-400">Carregando historico...</p>
          ) : historyRows.length ? (
            <div className="mt-3 space-y-2 text-sm">
              {historyRows.map((season) => (
                <div
                  key={String(season.season_id)}
                  className="rounded-md border border-slate-900 p-3"
                >
                  <p className="font-medium">{String(season.name ?? "Temporada")}</p>
                  <p className="text-slate-400">
                    Campeao: {String(season.champion_club_name ?? "Nao definido")}
                  </p>
                </div>
              ))}
            </div>
          ) : (
            <p className="mt-2 text-sm text-slate-400">Nenhuma temporada encerrada.</p>
          )}
        </section>
      </div>
    </main>
  );
}

function Info({ label, value }: { label: string; value: string }) {
  return (
    <div className="rounded-md border border-slate-900 p-3">
      <p className="text-xs uppercase text-slate-500">{label}</p>
      <p className="mt-1 font-medium">{value}</p>
    </div>
  );
}

function statusLabel(status: SeasonOperationalStatus): string {
  const labels: Record<SeasonOperationalStatus, string> = {
    waiting_for_clubs: "Aguardando clubes",
    ready_to_start: "Pronta para iniciar",
    active: "Ativa",
    finished: "Encerrada",
  };
  return labels[status];
}

function asSeasonRpcState(value: unknown): SeasonRpcState {
  const record = asRecord(value);
  return {
    operational_status: readStatus(record.operational_status),
    eligible_count: readNumber(record.eligible_count),
    required_count: readNumber(record.required_count),
    missing_count: readNumber(record.missing_count),
    active_season: record.active_season ?? null,
    current_round: record.current_round ?? null,
    next_round: record.next_round ?? null,
    previous_round: record.previous_round ?? null,
  };
}

function readStatus(value: unknown): SeasonOperationalStatus {
  if (
    value === "waiting_for_clubs" ||
    value === "ready_to_start" ||
    value === "active" ||
    value === "finished"
  ) {
    return value;
  }
  return "waiting_for_clubs";
}

function readNumber(value: unknown): number {
  return typeof value === "number" ? value : 0;
}

function readRecord(value: unknown): Record<string, unknown> | null {
  if (!value || typeof value !== "object" || Array.isArray(value)) return null;
  return value as Record<string, unknown>;
}

function asRecord(value: unknown): Record<string, unknown> {
  return readRecord(value) ?? {};
}
