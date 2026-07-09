import { createFileRoute, Link, useNavigate } from "@tanstack/react-router";
import { useQuery } from "@tanstack/react-query";
import { useServerFn } from "@tanstack/react-start";
import { useState } from "react";
import { getMatchEvents, getMe, getMyClub, listMatchSummaries } from "@/lib/game.functions";
import { supabase } from "@/integrations/supabase/client";
import { centsToReal } from "@/domain/rules/validators";
import { canRequestMatchEvents, mapMatchEventsErrorMessage } from "@/lib/match-access";

export const Route = createFileRoute("/_authenticated/app")({
  component: AppHome,
});

function AppHome() {
  const nav = useNavigate();
  const meFn = useServerFn(getMe);
  const clubFn = useServerFn(getMyClub);
  const matchesFn = useServerFn(listMatchSummaries);
  const eventsFn = useServerFn(getMatchEvents);
  const [openMatchId, setOpenMatchId] = useState<string | null>(null);

  const me = useQuery({ queryKey: ["me"], queryFn: () => meFn() });
  const club = useQuery({ queryKey: ["myClub"], queryFn: () => clubFn() });
  const profile = me.data?.profile;
  const isAdmin = me.data?.roles.includes("admin") ?? false;
  const matches = useQuery({
    queryKey: ["matchSummaries"],
    queryFn: () => matchesFn(),
    enabled: profile?.status === "approved",
  });
  const selectedSummary = matches.data?.matches.find((match) => match.match_id === openMatchId);
  const canViewSelectedEvents = selectedSummary
    ? canRequestMatchEvents({
        summary: selectedSummary,
        myClubId: club.data?.id ?? null,
        isAdmin,
      })
    : false;
  const events = useQuery({
    queryKey: ["matchEvents", openMatchId],
    queryFn: () => eventsFn({ data: { matchId: openMatchId ?? "" } }),
    enabled: Boolean(openMatchId) && canViewSelectedEvents,
  });

  if (me.isLoading)
    return (
      <Shell>
        <p>Carregando…</p>
      </Shell>
    );
  if (me.error)
    return (
      <Shell>
        <p className="text-red-400">Erro: {String(me.error)}</p>
      </Shell>
    );

  if (!profile)
    return (
      <Shell>
        <p>Perfil não encontrado.</p>
      </Shell>
    );

  if (profile.status !== "approved") {
    return (
      <Shell>
        <h2 className="text-lg font-semibold">Olá, {profile.username}</h2>
        <p className="mt-2 text-sm text-slate-400">
          Sua conta está com status <b>{profile.status}</b>. Aguarde o administrador liberar.
        </p>
        <button
          onClick={async () => {
            await supabase.auth.signOut();
            nav({ to: "/login" });
          }}
          className="mt-6 rounded-md border border-slate-700 px-3 py-1.5 text-sm"
        >
          Sair
        </button>
      </Shell>
    );
  }

  return (
    <Shell>
      <h2 className="text-lg font-semibold">Olá, {profile.username}</h2>
      <p className="mt-1 text-xs uppercase tracking-wider text-slate-500">
        {isAdmin ? "admin" : "usuário aprovado"}
      </p>

      <section className="mt-6 rounded-md border border-slate-800 p-4">
        <h3 className="font-medium">Seu clube</h3>
        {club.isLoading ? (
          <p className="mt-2 text-sm text-slate-400">Carregando…</p>
        ) : club.data ? (
          <div className="mt-2 space-y-1 text-sm">
            <p>
              <b>{club.data.name}</b> ({club.data.abbreviation})
            </p>
            <p>Saldo: {centsToReal(club.data.balance_cents)}</p>
            <Link to="/abrir-pacote" className="mt-2 inline-block underline">
              Abrir pacote inicial →
            </Link>
            <br />
            <Link to="/elenco" className="mt-2 inline-block underline">
              Ver elenco e escalacao →
            </Link>
            <br />
            <Link to="/classificacao" className="mt-2 inline-block underline">
              Ver classificacao →
            </Link>
          </div>
        ) : (
          <div className="mt-2 space-y-2">
            <p className="text-sm text-slate-400">Você ainda não tem clube.</p>
            <Link
              to="/criar-clube"
              className="rounded-md bg-slate-100 px-3 py-1.5 text-sm text-slate-900 inline-block"
            >
              Criar clube
            </Link>
          </div>
        )}
      </section>

      {isAdmin && (
        <section className="mt-6 rounded-md border border-slate-800 p-4">
          <h3 className="font-medium">Admin</h3>
          <Link to="/admin" className="underline text-sm">
            Painel administrativo →
          </Link>
        </section>
      )}

      <section className="mt-6 rounded-md border border-slate-800 p-4">
        <h3 className="font-medium">Partidas</h3>
        <Link to="/classificacao" className="mt-2 inline-block text-sm underline">
          Classificacao e temporada →
        </Link>
        {matches.isLoading ? (
          <p className="mt-2 text-sm text-slate-400">Carregando partidas...</p>
        ) : matches.error ? (
          <p className="mt-2 text-sm text-red-400">Nao foi possivel carregar as partidas.</p>
        ) : matches.data?.matches.length ? (
          <div className="mt-3 space-y-3">
            {matches.data.matches.map((match) => {
              const canViewEvents = canRequestMatchEvents({
                summary: match,
                myClubId: club.data?.id ?? null,
                isAdmin,
              });
              const isOpen = openMatchId === match.match_id;

              return (
                <article key={match.match_id} className="rounded-md border border-slate-900 p-3">
                  <div className="flex flex-wrap items-center justify-between gap-3">
                    <div>
                      <p className="text-xs text-slate-500">
                        {match.competition_name} - Rodada {match.round_number}
                      </p>
                      <p className="mt-1 text-sm">
                        <b>{match.home_club_abbreviation}</b> {match.home_goals} x{" "}
                        {match.away_goals} <b>{match.away_club_abbreviation}</b>
                      </p>
                    </div>
                    {canViewEvents ? (
                      <button
                        type="button"
                        onClick={() => setOpenMatchId(isOpen ? null : match.match_id)}
                        className="rounded-md border border-slate-700 px-2 py-1 text-xs"
                      >
                        {isOpen ? "Ocultar eventos" : "Ver eventos"}
                      </button>
                    ) : (
                      <p className="max-w-xs text-xs text-slate-500">
                        Eventos detalhados disponiveis somente para partidas do seu clube.
                      </p>
                    )}
                  </div>

                  {isOpen && canViewEvents && (
                    <div className="mt-3 border-t border-slate-900 pt-3 text-sm">
                      {events.isLoading ? (
                        <p className="text-slate-400">Carregando eventos...</p>
                      ) : events.error ? (
                        <p className="text-red-400">{mapMatchEventsErrorMessage(events.error)}</p>
                      ) : events.data?.events.length ? (
                        <ol className="space-y-1">
                          {events.data.events.map((event) => (
                            <li key={event.id}>
                              {event.minute}' - {event.event_type}
                            </li>
                          ))}
                        </ol>
                      ) : (
                        <p className="text-slate-400">Nenhum evento registrado.</p>
                      )}
                    </div>
                  )}
                </article>
              );
            })}
          </div>
        ) : (
          <p className="mt-2 text-sm text-slate-400">Nenhuma partida encontrada.</p>
        )}
      </section>

      <button
        onClick={async () => {
          await supabase.auth.signOut();
          nav({ to: "/login" });
        }}
        className="mt-8 rounded-md border border-slate-700 px-3 py-1.5 text-sm"
      >
        Sair
      </button>
    </Shell>
  );
}

function Shell({ children }: { children: React.ReactNode }) {
  return (
    <main className="min-h-screen bg-[#0b0f14] px-6 py-10 text-slate-100">
      <div className="mx-auto max-w-2xl">
        <h1 className="text-xl font-bold">BagreFut</h1>
        <div className="mt-6">{children}</div>
      </div>
    </main>
  );
}
