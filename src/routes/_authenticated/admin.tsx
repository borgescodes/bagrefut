import { createFileRoute } from "@tanstack/react-router";
import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import { useServerFn } from "@tanstack/react-start";
import { useEffect, useState } from "react";
import {
  DEFAULT_SEASON_TIMEZONE,
  getSeasonAdminActionState,
  type SeasonOperationalStatus,
} from "@/domain/season";
import {
  adminListPendingUsers,
  adminResetUserPassword,
  adminSetUserStatus,
} from "@/lib/admin.functions";
import {
  adminFinishSeason,
  adminGetSeasonSetup,
  adminSaveSeasonSetup,
  adminSetSeasonParticipants,
  adminStartSeason,
} from "@/lib/season.functions";
import {
  getCurrentRoundState,
  listMatchSummaries,
  simulateMatchAdmin,
  simulateRoundAdmin,
} from "@/lib/game.functions";

export const Route = createFileRoute("/_authenticated/admin")({
  component: AdminPage,
});

function AdminPage() {
  const listFn = useServerFn(adminListPendingUsers);
  const statusFn = useServerFn(adminSetUserStatus);
  const resetFn = useServerFn(adminResetUserPassword);
  const roundStateFn = useServerFn(getCurrentRoundState);
  const matchesFn = useServerFn(listMatchSummaries);
  const simulateMatchFn = useServerFn(simulateMatchAdmin);
  const simulateRoundFn = useServerFn(simulateRoundAdmin);
  const qc = useQueryClient();

  const list = useQuery({ queryKey: ["admin", "users"], queryFn: () => listFn() });
  const roundState = useQuery({
    queryKey: ["admin", "currentRound"],
    queryFn: () => roundStateFn(),
  });
  const matches = useQuery({
    queryKey: ["admin", "matchSummaries"],
    queryFn: () => matchesFn(),
  });
  const [tempPassword, setTempPassword] = useState<{ username: string; password: string } | null>(
    null,
  );
  const [copyFeedback, setCopyFeedback] = useState<string | null>(null);

  const setStatus = useMutation({
    mutationFn: (v: { userId: string; status: "approved" | "blocked" | "pending" }) =>
      statusFn({ data: v }),
    onSuccess: () => qc.invalidateQueries({ queryKey: ["admin", "users"] }),
  });

  const reset = useMutation({
    mutationFn: (userId: string) => resetFn({ data: { userId } }),
    onMutate: () => {
      setTempPassword(null);
      setCopyFeedback(null);
    },
    onSuccess: (data) => setTempPassword({ username: data.username, password: data.tempPassword }),
  });
  const runMatch = useMutation({
    mutationFn: (matchId: string) => simulateMatchFn({ data: { matchId } }),
    onSuccess: () => {
      void qc.invalidateQueries({ queryKey: ["admin", "matchSummaries"] });
      void qc.invalidateQueries({ queryKey: ["admin", "currentRound"] });
    },
  });
  const runRound = useMutation({
    mutationFn: (roundId: string) => simulateRoundFn({ data: { roundId } }),
    onSuccess: () => {
      void qc.invalidateQueries({ queryKey: ["admin", "matchSummaries"] });
      void qc.invalidateQueries({ queryKey: ["admin", "currentRound"] });
    },
  });

  const state = asRecord(roundState.data?.state);
  const currentRound = asRecord(state?.current_round);
  const currentRoundId = text(currentRound?.round_id, "");
  const currentRoundNumber = Number(text(currentRound?.round_number, "0"));
  const currentMatches =
    matches.data?.matches.filter((match) => match.round_number === currentRoundNumber) ?? [];

  async function copyPassword() {
    if (!tempPassword) return;
    await navigator.clipboard.writeText(tempPassword.password);
    setCopyFeedback("Senha copiada.");
  }

  function resetPasswordForUser(user: { id: string; username: string }) {
    if (!window.confirm(`Gerar senha temporária para ${user.username}?`)) return;
    reset.mutate(user.id);
  }

  if (list.isLoading) return <Shell>Carregando...</Shell>;
  if (list.error)
    return (
      <Shell>
        <p className="text-red-400">{adminErrorMessage(list.error)}</p>
      </Shell>
    );

  return (
    <Shell>
      <h1 className="text-xl font-bold">Painel administrativo</h1>
      <p className="mt-1 text-xs text-slate-500">
        Apenas admins. Ações registram log em admin_audit_logs.
      </p>

      <AdminSeasonSection />
      <section className="mt-6 rounded-md border border-slate-800 p-4">
        <div className="flex flex-wrap items-center justify-between gap-3">
          <div>
            <h2 className="font-medium">Simulacao de partidas</h2>
            <p className="mt-1 text-xs text-slate-500">
              Rodada atual: {currentRoundNumber > 0 ? currentRoundNumber : "indisponivel"} -{" "}
              {text(currentRound?.status, "sem status")}
            </p>
          </div>
          <button
            type="button"
            onClick={() => currentRoundId && runRound.mutate(currentRoundId)}
            disabled={!currentRoundId || runRound.isPending || currentMatches.length === 0}
            className="rounded-md border border-slate-700 px-2 py-1 text-xs disabled:opacity-60"
          >
            Simular rodada
          </button>
        </div>

        {roundState.error && (
          <p className="mt-3 text-sm text-red-400">{adminErrorMessage(roundState.error)}</p>
        )}
        {runMatch.error && (
          <p className="mt-3 text-sm text-red-400">{adminErrorMessage(runMatch.error)}</p>
        )}
        {runRound.error && (
          <p className="mt-3 text-sm text-red-400">{adminErrorMessage(runRound.error)}</p>
        )}
        {(runMatch.data || runRound.data) && (
          <p className="mt-3 text-xs text-emerald-300">Resultado atualizado.</p>
        )}

        <div className="mt-4 space-y-2 text-sm">
          {matches.isLoading ? (
            <p className="text-slate-400">Carregando partidas...</p>
          ) : currentMatches.length ? (
            currentMatches.map((match) => (
              <div
                key={match.match_id}
                className="flex flex-wrap items-center justify-between gap-3 rounded-md border border-slate-900 p-2"
              >
                <div>
                  <p className="text-xs text-slate-500">Status: {match.status}</p>
                  <p>
                    <b>{match.home_club_abbreviation}</b> {match.home_goals} x {match.away_goals}{" "}
                    <b>{match.away_club_abbreviation}</b>
                  </p>
                </div>
                <button
                  type="button"
                  onClick={() => runMatch.mutate(match.match_id)}
                  disabled={match.status === "finished" || runMatch.isPending || runRound.isPending}
                  className="rounded-md border border-slate-700 px-2 py-1 text-xs disabled:opacity-60"
                >
                  Simular partida
                </button>
              </div>
            ))
          ) : (
            <p className="text-slate-400">Nenhuma partida na rodada atual.</p>
          )}
        </div>
      </section>

      <table className="mt-6 w-full text-sm">
        <thead className="border-b border-slate-800 text-left text-xs uppercase text-slate-500">
          <tr>
            <th className="py-2">Username</th>
            <th>Status</th>
            <th className="text-right">Ações</th>
          </tr>
        </thead>
        <tbody>
          {list.data?.map((u) => (
            <tr key={u.id} className="border-b border-slate-900">
              <td className="py-2">{u.username}</td>
              <td>{u.status}</td>
              <td className="space-x-2 text-right">
                {u.status !== "approved" && (
                  <button
                    onClick={() => setStatus.mutate({ userId: u.id, status: "approved" })}
                    disabled={setStatus.isPending || reset.isPending}
                    className="rounded-md border border-slate-700 px-2 py-1 text-xs disabled:opacity-60"
                  >
                    Aprovar
                  </button>
                )}
                {u.status !== "blocked" && (
                  <button
                    onClick={() => setStatus.mutate({ userId: u.id, status: "blocked" })}
                    disabled={setStatus.isPending || reset.isPending}
                    className="rounded-md border border-slate-700 px-2 py-1 text-xs disabled:opacity-60"
                  >
                    Bloquear
                  </button>
                )}
                <button
                  onClick={() => resetPasswordForUser(u)}
                  disabled={reset.isPending || setStatus.isPending}
                  className="rounded-md border border-slate-700 px-2 py-1 text-xs disabled:opacity-60"
                >
                  Gerar senha temporária
                </button>
              </td>
            </tr>
          ))}
        </tbody>
      </table>

      {reset.error && <p className="mt-4 text-sm text-red-400">{adminErrorMessage(reset.error)}</p>}

      {tempPassword && (
        <div className="mt-6 rounded-md border border-amber-700 bg-amber-950/40 p-3 text-sm">
          <p>
            Senha temporária gerada para <b>{tempPassword.username}</b>
          </p>
          <code className="mt-2 block font-mono text-base">{tempPassword.password}</code>
          <p className="mt-2 text-xs text-amber-200">
            Copie agora e envie ao usuário por canal seguro. A senha não será mostrada novamente.
          </p>
          <div className="mt-3 flex flex-wrap gap-2">
            <button
              type="button"
              onClick={copyPassword}
              className="rounded-md border border-amber-600 px-2 py-1 text-xs"
            >
              Copiar senha
            </button>
            <button
              type="button"
              onClick={() => {
                setTempPassword(null);
                setCopyFeedback(null);
              }}
              className="rounded-md border border-slate-700 px-2 py-1 text-xs"
            >
              Fechar
            </button>
          </div>
          {copyFeedback && <p className="mt-2 text-xs text-amber-100">{copyFeedback}</p>}
        </div>
      )}
    </Shell>
  );
}

function AdminSeasonSection() {
  const setupFn = useServerFn(adminGetSeasonSetup);
  const saveSetupFn = useServerFn(adminSaveSeasonSetup);
  const saveParticipantsFn = useServerFn(adminSetSeasonParticipants);
  const startFn = useServerFn(adminStartSeason);
  const finishFn = useServerFn(adminFinishSeason);
  const qc = useQueryClient();

  const setup = useQuery({ queryKey: ["admin", "seasonSetup"], queryFn: () => setupFn() });
  const parsed = parseAdminSeasonSetup(setup.data);
  const [name, setName] = useState("Temporada 1");
  const [startDate, setStartDate] = useState("2026-08-01");
  const [matchTime, setMatchTime] = useState("22:00");
  const [intervalDays, setIntervalDays] = useState(1);
  const [registrationStatus, setRegistrationStatus] = useState<"open" | "closed">("open");
  const [registrationDeadline, setRegistrationDeadline] = useState("2026-07-31");
  const [prizes, setPrizes] = useState<number[]>([600, 500, 400, 300, 200, 100]);
  const [selectedClubIds, setSelectedClubIds] = useState<string[]>([]);

  useEffect(() => {
    const nextSetup = parseAdminSeasonSetup(setup.data);
    if (!nextSetup.config) return;
    setName(readString(nextSetup.config.name, "Temporada 1"));
    setStartDate(readString(nextSetup.config.start_date, "2026-08-01"));
    setMatchTime(readString(nextSetup.config.default_match_time, "22:00").slice(0, 5));
    setIntervalDays(readNumber(nextSetup.config.round_interval_days, 1));
    setRegistrationStatus(
      readString(nextSetup.config.registration_status, "open") === "closed" ? "closed" : "open",
    );
    setRegistrationDeadline(readString(nextSetup.config.registration_deadline, "2026-07-31"));
    if (nextSetup.prizes.length === 6) setPrizes(nextSetup.prizes);
    setSelectedClubIds(nextSetup.selectedClubIds);
  }, [setup.data]);

  const eligibleClubIds = parsed.eligibility
    .filter((club) => club.is_eligible)
    .map((club) => club.club_id);
  const configId = parsed.config ? readString(parsed.config.id, "") : "";
  const startState = getSeasonAdminActionState({
    operationalStatus: parsed.operationalStatus,
    selectedClubCount: selectedClubIds.length,
    configValid: name.trim().length >= 3 && prizes.length === 6,
    mutationPending: false,
  });

  const saveSetup = useMutation({
    mutationFn: () =>
      saveSetupFn({
        data: {
          name,
          startDate,
          defaultMatchTime: matchTime,
          roundIntervalDays: intervalDays,
          timezone: DEFAULT_SEASON_TIMEZONE,
          registrationStatus,
          registrationDeadline: registrationDeadline || null,
          prizesCents: prizes,
        },
      }),
    onSuccess: () => qc.invalidateQueries({ queryKey: ["admin", "seasonSetup"] }),
  });

  const saveParticipants = useMutation({
    mutationFn: () =>
      saveParticipantsFn({
        data: { configId, selectedClubIds, eligibleClubIds },
      }),
    onSuccess: () => qc.invalidateQueries({ queryKey: ["admin", "seasonSetup"] }),
  });

  const start = useMutation({
    mutationFn: () => startFn({ data: { configId } }),
    onSuccess: () => qc.invalidateQueries({ queryKey: ["admin", "seasonSetup"] }),
  });

  const finish = useMutation({
    mutationFn: () => finishFn({ data: {} }),
    onSuccess: () => qc.invalidateQueries({ queryKey: ["admin", "seasonSetup"] }),
  });

  const firstMutationError =
    saveSetup.error ?? saveParticipants.error ?? start.error ?? finish.error;

  function toggleClub(clubId: string) {
    setSelectedClubIds((current) =>
      current.includes(clubId)
        ? current.filter((id) => id !== clubId)
        : current.length < 6
          ? [...current, clubId]
          : current,
    );
  }

  return (
    <section className="mt-6 rounded-md border border-slate-800 p-4">
      <h2 className="font-medium">Temporada</h2>
      {setup.isLoading ? (
        <p className="mt-2 text-sm text-slate-400">Carregando configuração...</p>
      ) : setup.error ? (
        <p className="mt-2 text-sm text-red-400">{adminErrorMessage(setup.error)}</p>
      ) : (
        <div className="mt-4 space-y-5">
          <div className="grid gap-3 text-sm sm:grid-cols-3">
            <AdminInfo label="Estado" value={seasonStatusLabel(parsed.operationalStatus)} />
            <AdminInfo label="Elegiveis" value={`${parsed.eligibleCount} de 6`} />
            <AdminInfo label="Selecionados" value={`${selectedClubIds.length} de 6`} />
          </div>

          <div className="grid gap-3 sm:grid-cols-2">
            <TextField label="Nome" value={name} onChange={setName} />
            <TextField label="Data inicial" type="date" value={startDate} onChange={setStartDate} />
            <TextField label="Horario" type="time" value={matchTime} onChange={setMatchTime} />
            <TextField
              label="Intervalo entre rodadas"
              type="number"
              value={String(intervalDays)}
              onChange={(value) => setIntervalDays(Number(value))}
            />
            <label className="text-sm">
              <span className="mb-1 block text-xs uppercase text-slate-500">Inscricoes</span>
              <select
                value={registrationStatus}
                onChange={(event) =>
                  setRegistrationStatus(event.target.value === "closed" ? "closed" : "open")
                }
                className="w-full rounded-md border border-slate-700 bg-slate-950 px-3 py-2"
              >
                <option value="open">Abertas</option>
                <option value="closed">Fechadas</option>
              </select>
            </label>
            <TextField
              label="Limite inscricoes"
              type="date"
              value={registrationDeadline}
              onChange={setRegistrationDeadline}
            />
          </div>

          <div>
            <p className="text-xs uppercase text-slate-500">Premiacao por posicao (centavos)</p>
            <div className="mt-2 grid gap-2 sm:grid-cols-6">
              {prizes.map((amount, index) => (
                <label key={index} className="text-xs">
                  {index + 1}o
                  <input
                    type="number"
                    min={0}
                    step={1}
                    value={amount}
                    onChange={(event) => {
                      const next = [...prizes];
                      next[index] = Number(event.target.value);
                      setPrizes(next);
                    }}
                    className="mt-1 w-full rounded-md border border-slate-700 bg-slate-950 px-2 py-1"
                  />
                </label>
              ))}
            </div>
          </div>

          <div>
            <p className="text-xs uppercase text-slate-500">Clubes</p>
            <div className="mt-2 grid gap-2 sm:grid-cols-2">
              {parsed.eligibility.map((club) => (
                <label
                  key={club.club_id}
                  className="flex items-center justify-between gap-3 rounded-md border border-slate-900 p-2 text-sm"
                >
                  <span>
                    {club.club_name}{" "}
                    <span className="text-xs text-slate-500">
                      {club.is_eligible ? "elegivel" : (club.ineligible_reason ?? "pendente")}
                    </span>
                  </span>
                  <input
                    type="checkbox"
                    checked={selectedClubIds.includes(club.club_id)}
                    disabled={!club.is_eligible || parsed.operationalStatus === "active"}
                    onChange={() => toggleClub(club.club_id)}
                  />
                </label>
              ))}
            </div>
          </div>

          <div className="flex flex-wrap gap-2 text-sm">
            <button
              type="button"
              onClick={() => saveSetup.mutate()}
              disabled={saveSetup.isPending}
              className="rounded-md border border-slate-700 px-3 py-1.5 disabled:opacity-60"
            >
              Salvar configuracao
            </button>
            <button
              type="button"
              onClick={() => saveParticipants.mutate()}
              disabled={!configId || selectedClubIds.length !== 6 || saveParticipants.isPending}
              className="rounded-md border border-slate-700 px-3 py-1.5 disabled:opacity-60"
            >
              Salvar selecao
            </button>
            <button
              type="button"
              onClick={() => start.mutate()}
              disabled={!configId || startState.disabled || start.isPending}
              className="rounded-md border border-emerald-700 px-3 py-1.5 disabled:opacity-60"
            >
              Iniciar temporada
            </button>
            <button
              type="button"
              onClick={() => finish.mutate()}
              disabled={parsed.operationalStatus !== "active" || finish.isPending}
              className="rounded-md border border-amber-700 px-3 py-1.5 disabled:opacity-60"
            >
              Encerrar temporada
            </button>
          </div>

          {startState.reason && <p className="text-xs text-amber-300">{startState.reason}</p>}
          {firstMutationError && (
            <p className="text-sm text-red-400">{adminErrorMessage(firstMutationError)}</p>
          )}
        </div>
      )}
    </section>
  );
}

function adminErrorMessage(error: unknown): string {
  const message = error instanceof Error ? error.message : String(error);
  const messages: Record<string, string> = {
    profile_not_approved: "Sua conta ainda não está aprovada para ações administrativas.",
    forbidden_not_admin: "Você não tem permissão de administrador.",
    target_profile_not_found: "Usuário alvo não encontrado no cadastro.",
    target_auth_user_not_found: "Usuário alvo não encontrado no Auth.",
    password_update_failed: "Não foi possível atualizar a senha.",
    password_update_missing_user: "A atualização não retornou o usuário alterado.",
    season_name_invalid: "Nome da temporada invalido.",
    season_start_date_invalid: "Data inicial invalida.",
    season_match_time_invalid: "Horario padrao invalido.",
    season_round_interval_invalid: "Intervalo entre rodadas invalido.",
    season_timezone_invalid: "Timezone invalido.",
    season_prizes_invalid: "Premiacao invalida.",
    season_selection_requires_exactly_6: "Selecione exatamente 6 clubes.",
    season_selection_has_duplicates: "A selecao tem clube duplicado.",
    season_selection_has_ineligible_club: "A selecao tem clube inelegivel.",
    season_selected_club_ineligible: "Um dos clubes selecionados nao esta elegivel.",
    active_season_exists: "Ja existe uma temporada ativa.",
    season_has_pending_matches: "A temporada ainda tem partidas pendentes.",
    season_not_active: "Temporada nao esta ativa.",
    season_prize_already_credited: "A premiacao desta temporada ja foi creditada.",
    lineup_auto_insufficient_players: "Um clube nao tem jogadores elegiveis suficientes.",
    match_not_found: "Partida nao encontrada.",
    round_not_found: "Rodada nao encontrada.",
    match_not_simulable: "Partida nao esta em status simulavel.",
  };
  const code = Object.keys(messages).find((key) => message.includes(key));
  return code ? messages[code] : "Não foi possível concluir. Tente novamente.";
}

function AdminInfo({ label, value }: { label: string; value: string }) {
  return (
    <div className="rounded-md border border-slate-900 p-3">
      <p className="text-xs uppercase text-slate-500">{label}</p>
      <p className="mt-1 font-medium">{value}</p>
    </div>
  );
}

function TextField({
  label,
  value,
  onChange,
  type = "text",
}: {
  label: string;
  value: string;
  onChange: (value: string) => void;
  type?: string;
}) {
  return (
    <label className="text-sm">
      <span className="mb-1 block text-xs uppercase text-slate-500">{label}</span>
      <input
        type={type}
        value={value}
        onChange={(event) => onChange(event.target.value)}
        className="w-full rounded-md border border-slate-700 bg-slate-950 px-3 py-2"
      />
    </label>
  );
}

interface AdminSeasonSetup {
  operationalStatus: SeasonOperationalStatus;
  eligibleCount: number;
  config: Record<string, unknown> | null;
  eligibility: AdminEligibilityRow[];
  selectedClubIds: string[];
  prizes: number[];
}

interface AdminEligibilityRow {
  club_id: string;
  club_name: string;
  is_eligible: boolean;
  ineligible_reason: string | null;
}

function parseAdminSeasonSetup(value: unknown): AdminSeasonSetup {
  const root = readRecord(value);
  const state = readRecord(root.operational_state);
  const config = readNullableRecord(root.config);
  const eligibility = readArray(root.eligibility).map(parseEligibilityRow);
  const selectedClubIds = readArray(root.selected_club_ids)
    .map((item) => (typeof item === "string" ? item : ""))
    .filter(Boolean);
  const prizes = readArray(root.prizes)
    .map((item) => (typeof item === "number" ? item : null))
    .filter((item): item is number => item !== null);

  return {
    operationalStatus: readOperationalStatus(state.operational_status),
    eligibleCount: readNumber(state.eligible_count, 0),
    config,
    eligibility,
    selectedClubIds,
    prizes,
  };
}

function parseEligibilityRow(value: unknown): AdminEligibilityRow {
  const row = readRecord(value);
  return {
    club_id: readString(row.club_id, ""),
    club_name: readString(row.club_name, "Clube"),
    is_eligible: row.is_eligible === true,
    ineligible_reason: typeof row.ineligible_reason === "string" ? row.ineligible_reason : null,
  };
}

function seasonStatusLabel(status: SeasonOperationalStatus): string {
  const labels: Record<SeasonOperationalStatus, string> = {
    waiting_for_clubs: "Aguardando clubes",
    ready_to_start: "Pronta para iniciar",
    active: "Ativa",
    finished: "Encerrada",
  };
  return labels[status];
}

function readOperationalStatus(value: unknown): SeasonOperationalStatus {
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

function readNullableRecord(value: unknown): Record<string, unknown> | null {
  if (value === null || value === undefined) return null;
  return readRecord(value);
}

function readRecord(value: unknown): Record<string, unknown> {
  if (!value || typeof value !== "object" || Array.isArray(value)) return {};
  return value as Record<string, unknown>;
}

function readArray(value: unknown): unknown[] {
  return Array.isArray(value) ? value : [];
}

function readString(value: unknown, fallback: string): string {
  return typeof value === "string" ? value : fallback;
}

function readNumber(value: unknown, fallback: number): number {
  return typeof value === "number" ? value : fallback;
}

function asRecord(value: unknown): Record<string, unknown> | null {
  if (!value || typeof value !== "object" || Array.isArray(value)) return null;
  return value as Record<string, unknown>;
}

function text(value: unknown, fallback: string): string {
  if (typeof value === "string" || typeof value === "number" || typeof value === "boolean") {
    return String(value);
  }
  return fallback;
}

function Shell({ children }: { children: React.ReactNode }) {
  return (
    <main className="min-h-screen bg-[#0b0f14] px-6 py-10 text-slate-100">
      <div className="mx-auto max-w-3xl">{children}</div>
    </main>
  );
}
