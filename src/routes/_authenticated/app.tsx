import { createFileRoute, Link, useNavigate } from "@tanstack/react-router";
import { useQuery } from "@tanstack/react-query";
import { useServerFn } from "@tanstack/react-start";
import { getMe, getMyClub } from "@/lib/game.functions";
import { supabase } from "@/integrations/supabase/client";
import { centsToReal } from "@/domain/rules/validators";

export const Route = createFileRoute("/_authenticated/app")({
  component: AppHome,
});

function AppHome() {
  const nav = useNavigate();
  const meFn = useServerFn(getMe);
  const clubFn = useServerFn(getMyClub);

  const me = useQuery({ queryKey: ["me"], queryFn: () => meFn() });
  const club = useQuery({ queryKey: ["myClub"], queryFn: () => clubFn() });

  if (me.isLoading) return <Shell><p>Carregando…</p></Shell>;
  if (me.error) return <Shell><p className="text-red-400">Erro: {String(me.error)}</p></Shell>;
  const profile = me.data?.profile;
  const isAdmin = me.data?.roles.includes("admin") ?? false;

  if (!profile) return <Shell><p>Perfil não encontrado.</p></Shell>;

  if (profile.status !== "approved") {
    return (
      <Shell>
        <h2 className="text-lg font-semibold">Olá, {profile.username}</h2>
        <p className="mt-2 text-sm text-slate-400">
          Sua conta está com status <b>{profile.status}</b>. Aguarde o administrador liberar.
        </p>
        <button
          onClick={async () => { await supabase.auth.signOut(); nav({ to: "/login" }); }}
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
            <p><b>{club.data.name}</b> ({club.data.abbreviation})</p>
            <p>Saldo: {centsToReal(club.data.balance_cents)}</p>
            <Link to="/abrir-pacote" className="mt-2 inline-block underline">Abrir pacote inicial →</Link>
          </div>
        ) : (
          <div className="mt-2 space-y-2">
            <p className="text-sm text-slate-400">Você ainda não tem clube.</p>
            <Link to="/criar-clube" className="rounded-md bg-slate-100 px-3 py-1.5 text-sm text-slate-900 inline-block">
              Criar clube
            </Link>
          </div>
        )}
      </section>

      {isAdmin && (
        <section className="mt-6 rounded-md border border-slate-800 p-4">
          <h3 className="font-medium">Admin</h3>
          <Link to="/admin" className="underline text-sm">Painel administrativo →</Link>
        </section>
      )}

      <button
        onClick={async () => { await supabase.auth.signOut(); nav({ to: "/login" }); }}
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
