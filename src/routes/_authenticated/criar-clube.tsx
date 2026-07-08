import { createFileRoute, useNavigate } from "@tanstack/react-router";
import { useState } from "react";
import { useQuery } from "@tanstack/react-query";
import { useServerFn } from "@tanstack/react-start";
import { createClub, listBadges } from "@/lib/game.functions";
import { validateAbbreviation, validateClubName } from "@/domain/rules/validators";

export const Route = createFileRoute("/_authenticated/criar-clube")({
  component: CreateClubPage,
});

function CreateClubPage() {
  const nav = useNavigate();
  const badgesFn = useServerFn(listBadges);
  const createFn = useServerFn(createClub);
  const badges = useQuery({ queryKey: ["badges"], queryFn: () => badgesFn() });

  const [name, setName] = useState("");
  const [abbr, setAbbr] = useState("");
  const [badgeCode, setBadgeCode] = useState("");
  const [error, setError] = useState<string | null>(null);
  const [busy, setBusy] = useState(false);

  async function handleSubmit(e: React.FormEvent) {
    e.preventDefault();
    setError(null);
    const n = validateClubName(name);
    if (!n.ok) return setError(n.error);
    const a = validateAbbreviation(abbr);
    if (!a.ok) return setError(a.error);
    if (!badgeCode) return setError("Escolha um escudo");
    setBusy(true);
    try {
      await createFn({ data: { name: name.trim(), abbreviation: abbr.toUpperCase(), badgeCode } });
      nav({ to: "/app" });
    } catch (err) {
      setError(err instanceof Error ? err.message : String(err));
    } finally {
      setBusy(false);
    }
  }

  return (
    <main className="min-h-screen bg-[#0b0f14] px-6 py-10 text-slate-100">
      <div className="mx-auto max-w-2xl">
        <h1 className="text-xl font-bold">Criar clube</h1>
        <form onSubmit={handleSubmit} className="mt-6 space-y-4">
          <label className="block text-sm">
            <span className="mb-1 block">Nome (3-24)</span>
            <input
              value={name}
              onChange={(e) => setName(e.target.value)}
              className="w-full rounded-md border border-slate-700 bg-slate-900 px-3 py-2"
            />
          </label>
          <label className="block text-sm">
            <span className="mb-1 block">Sigla (2-4 letras)</span>
            <input
              value={abbr}
              onChange={(e) => setAbbr(e.target.value.toUpperCase())}
              className="w-full rounded-md border border-slate-700 bg-slate-900 px-3 py-2 uppercase"
            />
          </label>
          <div>
            <p className="text-sm mb-2">Escudo</p>
            <div className="grid grid-cols-4 gap-3 sm:grid-cols-7">
              {badges.data?.map((b) => (
                <button
                  type="button"
                  key={b.code}
                  onClick={() => setBadgeCode(b.code)}
                  className={`rounded-md border p-1 ${badgeCode === b.code ? "border-slate-100" : "border-slate-700"}`}
                >
                  <img src={b.asset_path} alt={b.label} className="h-14 w-14 mx-auto" />
                </button>
              ))}
            </div>
          </div>
          {error && <p className="text-sm text-red-400">{error}</p>}
          <button
            type="submit"
            disabled={busy}
            className="rounded-md bg-slate-100 px-4 py-2 text-sm font-medium text-slate-900 disabled:opacity-60"
          >
            {busy ? "Criando..." : "Criar clube (recebe R$ 10,00 + pacote fechado)"}
          </button>
        </form>
      </div>
    </main>
  );
}
