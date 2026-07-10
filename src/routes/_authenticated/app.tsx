import { useQuery } from "@tanstack/react-query";
import { createFileRoute, Link } from "@tanstack/react-router";
import { useServerFn } from "@tanstack/react-start";
import {
  ArrowRight,
  CalendarClock,
  CheckCircle2,
  Clock3,
  PackageOpen,
  Shield,
  ShoppingBag,
  Trophy,
  UsersRound,
} from "lucide-react";
import { useMemo, useState, type ReactNode } from "react";
import type { JsonValue, MatchScoreSummary } from "@/domain/types";
import { centsToReal } from "@/domain/rules/validators";
import {
  getCurrentRoundState,
  getMatchEvents,
  getMatchPublicDetails,
  getMe,
  getMyClub,
  listMatchSummaries,
} from "@/lib/game.functions";
import { getInitialPackExperience } from "@/lib/pack.functions";
import { getLineupWorkspace } from "@/lib/lineup.functions";
import { canRequestMatchEvents, mapMatchEventsErrorMessage } from "@/lib/match-access";
import { formatPlayStyleName } from "@/lib/display-labels";
import { PageHeader, SectionHeader } from "@/components/page/PageHeader";
import { EmptyState, ErrorState, PageSkeleton } from "@/components/feedback/PageStates";
import {
  Dialog,
  DialogContent,
  DialogDescription,
  DialogHeader,
  DialogTitle,
} from "@/components/ui/dialog";

export const Route = createFileRoute("/_authenticated/app")({ component: AppHome });

function AppHome() {
  const meFn = useServerFn(getMe);
  const clubFn = useServerFn(getMyClub);
  const matchesFn = useServerFn(listMatchSummaries);
  const eventsFn = useServerFn(getMatchEvents);
  const detailsFn = useServerFn(getMatchPublicDetails);
  const roundFn = useServerFn(getCurrentRoundState);
  const packFn = useServerFn(getInitialPackExperience);
  const lineupFn = useServerFn(getLineupWorkspace);
  const [openMatchId, setOpenMatchId] = useState<string | null>(null);

  const me = useQuery({ queryKey: ["me"], queryFn: () => meFn() });
  const club = useQuery({ queryKey: ["myClub"], queryFn: () => clubFn() });
  const approved = me.data?.profile?.status === "approved";
  const isAdmin = me.data?.roles.includes("admin") ?? false;
  const matches = useQuery({
    queryKey: ["matchSummaries"],
    queryFn: () => matchesFn(),
    enabled: approved,
  });
  const round = useQuery({
    queryKey: ["round", "current"],
    queryFn: () => roundFn(),
    enabled: approved,
  });
  const pack = useQuery({
    queryKey: ["initialPackExperience"],
    queryFn: () => packFn(),
    enabled: approved && Boolean(club.data),
  });
  const lineup = useQuery({
    queryKey: ["lineupWorkspace"],
    queryFn: () => lineupFn(),
    enabled: approved && Boolean(club.data),
  });
  const selectedSummary =
    matches.data?.matches.find((match) => match.match_id === openMatchId) ?? null;
  const canViewSelectedEvents = selectedSummary
    ? canRequestMatchEvents({ summary: selectedSummary, myClubId: club.data?.id ?? null, isAdmin })
    : false;
  const events = useQuery({
    queryKey: ["matchEvents", openMatchId],
    queryFn: () => eventsFn({ data: { matchId: openMatchId ?? "" } }),
    enabled: Boolean(openMatchId) && canViewSelectedEvents,
  });
  const publicDetails = useQuery({
    queryKey: ["matchPublicDetails", openMatchId],
    queryFn: () => detailsFn({ data: { matchId: openMatchId ?? "" } }),
    enabled: Boolean(openMatchId),
  });

  const orderedMatches = useMemo(
    () =>
      [...(matches.data?.matches ?? [])].sort(
        (a, b) => new Date(b.starts_at).getTime() - new Date(a.starts_at).getTime(),
      ),
    [matches.data?.matches],
  );
  const recentMatches = orderedMatches.filter((match) => match.status === "finished").slice(0, 4);
  const nextMatch =
    [...orderedMatches]
      .reverse()
      .find((match) => match.status === "scheduled" || match.status === "live") ?? null;
  const roundRecord = asRecord(asRecord(round.data?.state)?.current_round);

  if (me.isLoading || club.isLoading)
    return (
      <main>
        <PageSkeleton rows={4} />
      </main>
    );
  if (me.error)
    return (
      <main className="px-4 py-8">
        <ErrorState
          description="Não foi possível carregar seu perfil."
          onRetry={() => void me.refetch()}
        />
      </main>
    );
  if (!me.data?.profile)
    return (
      <main className="px-4 py-8">
        <ErrorState
          title="Perfil não encontrado"
          description="Saia e entre novamente para atualizar sua sessão."
        />
      </main>
    );
  if (me.data.profile.status !== "approved")
    return <PendingAccount username={me.data.profile.username} status={me.data.profile.status} />;

  return (
    <main className="home-page min-h-screen bg-[#0b0f14] px-4 py-8 text-slate-100 sm:px-6">
      <div className="mx-auto max-w-6xl">
        <PageHeader
          eyebrow="Visão do clube"
          title={`Olá, ${me.data.profile.username}`}
          description="O que precisa da sua atenção antes da próxima rodada."
        />

        {!club.data ? (
          <EmptyState
            title="Seu clube começa aqui"
            description="Crie a identidade do time para receber o pacote inicial e entrar no Bagreleirão."
          />
        ) : (
          <>
            <section className="home-club-hero">
              <div className="home-club-hero__identity">
                <span className="home-club-hero__badge" aria-hidden="true">
                  {club.data.abbreviation}
                </span>
                <div>
                  <p>Seu clube</p>
                  <h2>{club.data.name}</h2>
                  <span>{club.data.abbreviation}</span>
                </div>
              </div>
              <div className="home-club-hero__stats">
                <HomeStat label="Saldo" value={centsToReal(club.data.balance_cents)} />
                <HomeStat
                  label="Elenco"
                  value={lineup.isLoading ? "—" : `${lineup.data?.roster.length ?? 0} cartas`}
                />
                <HomeStat
                  label="Pacote"
                  value={pack.isLoading ? "—" : pack.data?.pack?.openedAt ? "Aberto" : "Pendente"}
                  attention={!pack.data?.pack?.openedAt}
                />
              </div>
            </section>

            <div className="home-grid">
              <section className="home-panel home-round-panel">
                <SectionHeader
                  title="Rodada atual"
                  description="Prazo e situação operacional da escalação."
                />
                {round.isLoading ? (
                  <PageSkeleton rows={2} />
                ) : round.error ? (
                  <ErrorState
                    description="Não foi possível consultar a rodada."
                    onRetry={() => void round.refetch()}
                  />
                ) : roundRecord ? (
                  <div className="home-round-grid">
                    <HomeStat label="Rodada" value={String(roundRecord.round_number ?? "—")} />
                    <HomeStat
                      label="Escalação até"
                      value={formatDateTime(roundRecord.lineup_lock_at)}
                    />
                    <HomeStat label="Início" value={formatDateTime(roundRecord.starts_at)} />
                  </div>
                ) : (
                  <EmptyState
                    title="Entre rodadas"
                    description="A próxima rodada ainda não foi disponibilizada."
                  />
                )}
                <Link to="/elenco" className="home-panel__link">
                  Ajustar escalação <ArrowRight size={16} aria-hidden="true" />
                </Link>
              </section>

              <section className="home-panel home-next-match">
                <SectionHeader title="Próximo jogo" />
                {matches.isLoading ? (
                  <PageSkeleton rows={1} />
                ) : nextMatch ? (
                  <MatchCard
                    match={nextMatch}
                    onOpen={() => setOpenMatchId(nextMatch.match_id)}
                    highlightedClubId={club.data.id}
                  />
                ) : (
                  <EmptyState
                    title="Sem jogo agendado"
                    description="Quando a tabela for definida, o próximo confronto aparece aqui."
                  />
                )}
              </section>
            </div>

            <section className="home-actions" aria-label="Atalhos">
              <QuickAction
                to="/elenco"
                icon={UsersRound}
                label="Elenco"
                description="Cartas e escalação"
              />
              <QuickAction
                to="/mercado"
                icon={ShoppingBag}
                label="Mercado"
                description="Treino e negócios"
              />
              <QuickAction
                to="/classificacao"
                icon={Trophy}
                label="Tabela"
                description="Temporada e histórico"
              />
              <QuickAction
                to="/abrir-pacote"
                icon={PackageOpen}
                label="Pacote"
                description={pack.data?.pack?.openedAt ? "Rever cartas" : "Abrir agora"}
              />
            </section>

            <section className="home-panel home-recent">
              <SectionHeader
                title="Partidas recentes"
                description="Placar, escalações usadas e estatísticas disponíveis."
              />
              {matches.isLoading ? (
                <PageSkeleton rows={3} />
              ) : matches.error ? (
                <ErrorState
                  description="Não foi possível carregar as partidas."
                  onRetry={() => void matches.refetch()}
                />
              ) : recentMatches.length ? (
                <div className="home-match-list">
                  {recentMatches.map((match) => (
                    <MatchCard
                      key={match.match_id}
                      match={match}
                      onOpen={() => setOpenMatchId(match.match_id)}
                      highlightedClubId={club.data?.id}
                    />
                  ))}
                </div>
              ) : (
                <EmptyState
                  title="Nenhum resultado ainda"
                  description="Os placares concluídos aparecerão aqui."
                />
              )}
            </section>
          </>
        )}
      </div>

      <MatchDetailDialog
        match={selectedSummary}
        open={Boolean(openMatchId)}
        onOpenChange={(open) => !open && setOpenMatchId(null)}
        details={publicDetails.data?.details ?? null}
        detailsLoading={publicDetails.isLoading}
        detailsError={Boolean(publicDetails.error)}
        canViewEvents={canViewSelectedEvents}
        events={events.data?.events ?? []}
        eventsLoading={events.isLoading}
        eventsError={events.error}
      />
    </main>
  );
}

function PendingAccount({ username, status }: { username: string; status: string }) {
  const blocked = status === "blocked";
  return (
    <main className="px-4 py-8">
      <div className="mx-auto max-w-xl rounded-lg border border-border bg-card p-6 text-center">
        <span className="mx-auto grid size-12 place-items-center rounded-lg border border-border bg-background text-warning">
          {blocked ? <Shield aria-hidden="true" /> : <Clock3 aria-hidden="true" />}
        </span>
        <h1 className="mt-4 text-xl font-semibold">Olá, {username}</h1>
        <p className="mt-2 text-sm text-muted-foreground">
          {blocked
            ? "Sua conta está bloqueada. Fale com o administrador para revisar o acesso."
            : "Sua conta aguarda aprovação. Entre novamente após a liberação do administrador."}
        </p>
      </div>
    </main>
  );
}

function HomeStat({
  label,
  value,
  attention = false,
}: {
  label: string;
  value: string;
  attention?: boolean;
}) {
  return (
    <div className="home-stat" data-attention={attention || undefined}>
      <span>{label}</span>
      <strong className="tabular-nums">{value}</strong>
    </div>
  );
}

function QuickAction({
  to,
  icon: Icon,
  label,
  description,
}: {
  to: "/elenco" | "/mercado" | "/classificacao" | "/abrir-pacote";
  icon: typeof Trophy;
  label: string;
  description: string;
}) {
  return (
    <Link to={to} className="home-quick-action">
      <Icon aria-hidden="true" />
      <span>
        <strong>{label}</strong>
        <small>{description}</small>
      </span>
      <ArrowRight size={16} aria-hidden="true" />
    </Link>
  );
}

function MatchCard({
  match,
  onOpen,
  highlightedClubId,
}: {
  match: MatchScoreSummary;
  onOpen: () => void;
  highlightedClubId?: string;
}) {
  return (
    <button
      type="button"
      className="home-match-card"
      onClick={onOpen}
      aria-label={`Abrir detalhes de ${match.home_club_name} contra ${match.away_club_name}`}
    >
      <span className="home-match-card__meta">
        <span>
          {match.competition_name} · Rodada {match.round_number}
        </span>
        <span>{matchStatusLabel(match.status)}</span>
      </span>
      <span className="home-match-card__score">
        <span data-user={match.home_club_id === highlightedClubId || undefined}>
          <ClubBadge
            path={match.home_club_badge_path}
            abbreviation={match.home_club_abbreviation}
          />
          <strong>{match.home_club_abbreviation}</strong>
        </span>
        <b>
          {match.home_goals} <small>×</small> {match.away_goals}
        </b>
        <span data-user={match.away_club_id === highlightedClubId || undefined}>
          <ClubBadge
            path={match.away_club_badge_path}
            abbreviation={match.away_club_abbreviation}
          />
          <strong>{match.away_club_abbreviation}</strong>
        </span>
      </span>
      <span className="home-match-card__date">
        <CalendarClock size={14} aria-hidden="true" />
        {formatDateTime(match.starts_at)}
      </span>
    </button>
  );
}

function ClubBadge({ path, abbreviation }: { path: string | null; abbreviation: string }) {
  return path ? (
    <img src={path} alt={`Escudo ${abbreviation}`} loading="lazy" />
  ) : (
    <span aria-hidden="true">{abbreviation.slice(0, 3)}</span>
  );
}

function MatchDetailDialog({
  match,
  open,
  onOpenChange,
  details,
  detailsLoading,
  detailsError,
  canViewEvents,
  events,
  eventsLoading,
  eventsError,
}: {
  match: MatchScoreSummary | null;
  open: boolean;
  onOpenChange: (open: boolean) => void;
  details: JsonValue | null;
  detailsLoading: boolean;
  detailsError: boolean;
  canViewEvents: boolean;
  events: Array<{ id: string; minute: number; event_type: string }>;
  eventsLoading: boolean;
  eventsError: unknown;
}) {
  if (!match) return null;
  const record = asRecord(details);
  const statistics = asArray(record?.statistics);
  const lineups = asArray(record?.lineups);
  return (
    <Dialog open={open} onOpenChange={onOpenChange}>
      <DialogContent className="match-detail-dialog">
        <DialogHeader>
          <DialogTitle>
            {match.home_club_name} × {match.away_club_name}
          </DialogTitle>
          <DialogDescription>
            {match.competition_name} · Rodada {match.round_number} ·{" "}
            {formatDateTime(match.starts_at)}
          </DialogDescription>
        </DialogHeader>
        <div className="match-detail-score">
          <div>
            <ClubBadge
              path={match.home_club_badge_path}
              abbreviation={match.home_club_abbreviation}
            />
            <strong>{match.home_club_abbreviation}</strong>
          </div>
          <p>
            {match.home_goals}
            <span>×</span>
            {match.away_goals}
          </p>
          <div>
            <ClubBadge
              path={match.away_club_badge_path}
              abbreviation={match.away_club_abbreviation}
            />
            <strong>{match.away_club_abbreviation}</strong>
          </div>
        </div>
        {detailsLoading ? (
          <PageSkeleton rows={2} />
        ) : detailsError ? (
          <ErrorState description="Não foi possível carregar os detalhes." />
        ) : (
          <div className="match-detail-sections">
            <DetailSection title="Escalações usadas">
              {lineups.length ? (
                <div className="match-lineups">
                  {groupLineups(lineups).map((lineup) => (
                    <div key={lineup.clubId}>
                      <strong>{clubName(match, lineup.clubId)}</strong>
                      <span>
                        {humanLabel(lineup.origin)} · {lineup.formation} ·{" "}
                        {formatPlayStyleName(lineup.style)}
                      </span>
                      <small>{lineup.count} jogadores</small>
                    </div>
                  ))}
                </div>
              ) : (
                <p>Escalações ainda não disponíveis.</p>
              )}
            </DetailSection>
            <DetailSection title="Estatísticas">
              {statistics.length ? (
                <div className="match-statistics">
                  {statistics.map((item, index) => {
                    const stat = asRecord(item);
                    if (!stat) return null;
                    return (
                      <div key={index}>
                        <strong>{clubName(match, text(stat.club_id, ""))}</strong>
                        <span>
                          Posse <b>{text(stat.possession, "0")}%</b>
                        </span>
                        <span>
                          Finalizações <b>{text(stat.shots, "0")}</b>
                        </span>
                        <span>
                          No alvo <b>{text(stat.shots_on_target, "0")}</b>
                        </span>
                        <span>
                          Defesas <b>{text(stat.saves, "0")}</b>
                        </span>
                      </div>
                    );
                  })}
                </div>
              ) : (
                <p>Estatísticas ainda não disponíveis.</p>
              )}
            </DetailSection>
            <DetailSection title="Eventos">
              {!canViewEvents ? (
                <p>Eventos detalhados são restritos aos clubes participantes desta partida.</p>
              ) : eventsLoading ? (
                <PageSkeleton rows={2} />
              ) : eventsError ? (
                <p className="text-red-300">{mapMatchEventsErrorMessage(eventsError)}</p>
              ) : events.length ? (
                <ol className="match-events">
                  {events.map((event) => (
                    <li key={event.id}>
                      <time>{event.minute}′</time>
                      <span>{eventLabel(event.event_type)}</span>
                    </li>
                  ))}
                </ol>
              ) : (
                <p>Nenhum evento registrado.</p>
              )}
            </DetailSection>
          </div>
        )}
      </DialogContent>
    </Dialog>
  );
}

function DetailSection({ title, children }: { title: string; children: ReactNode }) {
  return (
    <section>
      <h3>{title}</h3>
      <div>{children}</div>
    </section>
  );
}

function groupLineups(items: unknown[]) {
  const groups = new Map<
    string,
    { clubId: string; origin: string; formation: string; style: string; count: number }
  >();
  for (const item of items) {
    const row = asRecord(item);
    if (!row) continue;
    const clubId = text(row.club_id, "clube");
    const current = groups.get(clubId);
    if (current) current.count += 1;
    else
      groups.set(clubId, {
        clubId,
        origin: text(row.lineup_origin, "manual"),
        formation: text(row.formation, "—"),
        style: text(row.play_style, "balanced"),
        count: 1,
      });
  }
  return [...groups.values()];
}

function clubName(match: MatchScoreSummary, clubId: string) {
  if (clubId === match.home_club_id) return match.home_club_name;
  if (clubId === match.away_club_id) return match.away_club_name;
  return "Clube";
}
function eventLabel(value: string) {
  return (
    (
      {
        match_started: "Início da partida",
        chance: "Chance criada",
        shot: "Finalização",
        save: "Defesa",
        goal: "Gol",
        halftime: "Intervalo",
        match_finished: "Fim de jogo",
        pressure: "Pressão ofensiva",
      } as Record<string, string>
    )[value] ?? humanLabel(value)
  );
}
function matchStatusLabel(value: string) {
  return (
    (
      {
        scheduled: "Agendada",
        live: "Ao vivo",
        finished: "Encerrada",
        cancelled: "Cancelada",
      } as Record<string, string>
    )[value] ?? humanLabel(value)
  );
}
function humanLabel(value: string) {
  return value
    .replace(/[_-]+/g, " ")
    .replace(/\s+/g, " ")
    .trim()
    .replace(/^./, (char) => char.toLocaleUpperCase("pt-BR"));
}
function formatDateTime(value: unknown) {
  if (typeof value !== "string" || !value) return "A definir";
  const date = new Date(value);
  return Number.isNaN(date.getTime())
    ? "A definir"
    : new Intl.DateTimeFormat("pt-BR", { dateStyle: "short", timeStyle: "short" }).format(date);
}
function asRecord(value: unknown): Record<string, unknown> | null {
  return value && typeof value === "object" && !Array.isArray(value)
    ? (value as Record<string, unknown>)
    : null;
}
function asArray(value: unknown): unknown[] {
  return Array.isArray(value) ? value : [];
}
function text(value: unknown, fallback: string): string {
  return typeof value === "string" || typeof value === "number" ? String(value) : fallback;
}
