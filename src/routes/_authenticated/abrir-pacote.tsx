import { createFileRoute, useNavigate } from "@tanstack/react-router";
import { useState } from "react";
import { useQuery } from "@tanstack/react-query";
import { useServerFn } from "@tanstack/react-start";
import { getMyClub, openInitialPack } from "@/lib/game.functions";

export const Route = createFileRoute("/_authenticated/abrir-pacote")({
  component: OpenPackPage,
});

function OpenPackPage() {
  const nav = useNavigate();
  const clubFn = useServerFn(getMyClub);
  const openFn = useServerFn(openInitialPack);
  const club = useQuery({ queryKey: ["myClub"], queryFn: () => clubFn() });

  const [items, setItems] = useState<Array<{ player_id: string; slot: number }> | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [busy, setBusy] = useState(false);

  async function open() {
    if (!club.data) return;
    setError(null);
    setBusy(true);
    try {
      const res = await openFn({ data: { clubId: club.data.id } });
      setItems(res.items as Array<{ player_id: string; slot: number }>);
    } catch (err) {
      setError(err instanceof Error ? err.message : String(err));
    } finally {
      setBusy(false);
    }
  }

  return (
    <main className="min-h-screen bg-[#0b0f14] px-6 py-10 text-slate-100">
      <div className="mx-auto max-w-2xl">
        <h1 className="text-xl font-bold">Abrir pacote inicial</h1>
        {!club.data ? (
          <p className="mt-6 text-sm text-slate-400">Você ainda não tem clube.</p>
        ) : (
          <>
            <p className="mt-4 text-sm text-slate-300">
              Clube: <b>{club.data.name}</b>. O pacote entrega 10 cartas aleatórias, sem repetir e
              sem reroll.
            </p>
            <button
              onClick={open}
              disabled={busy || !!items}
              className="mt-6 rounded-md bg-slate-100 px-4 py-2 text-sm font-medium text-slate-900 disabled:opacity-60"
            >
              {busy ? "Abrindo..." : items ? "Pacote já aberto" : "Abrir agora"}
            </button>
            {error && <p className="mt-4 text-sm text-red-400">{error}</p>}
            {items && (
              <ul className="mt-6 grid grid-cols-2 gap-2 text-sm sm:grid-cols-5">
                {items.map((it) => (
                  <li key={it.slot} className="rounded-md border border-slate-800 p-2">
                    <div className="text-xs text-slate-500">slot {it.slot}</div>
                    <div className="font-mono text-xs">{it.player_id.slice(0, 8)}…</div>
                  </li>
                ))}
              </ul>
            )}
            <button onClick={() => nav({ to: "/app" })} className="mt-8 text-sm underline">
              ← Voltar
            </button>
          </>
        )}
      </div>
    </main>
  );
}
