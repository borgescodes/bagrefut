import { createFileRoute, Link, useNavigate } from "@tanstack/react-router";
import { useState } from "react";
import { useQuery } from "@tanstack/react-query";
import { useServerFn } from "@tanstack/react-start";
import { ArrowLeft, Check, Shield } from "lucide-react";
import { createClub, listBadges } from "@/lib/game.functions";
import { validateAbbreviation, validateClubName } from "@/domain/rules/validators";
import { PageHeader } from "@/components/page/PageHeader";
import { PageSkeleton } from "@/components/feedback/PageStates";

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
  const selectedBadge = badges.data?.find((badge) => badge.code === badgeCode);

  async function handleSubmit(e: React.FormEvent) {
    e.preventDefault();
    if (busy) return;
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
      setError(createClubErrorMessage(err));
    } finally {
      setBusy(false);
    }
  }

  return (
    <main className="min-h-screen bg-[#0b0f14] px-4 py-8 text-slate-100 sm:px-6">
      <div className="mx-auto max-w-5xl">
        <PageHeader
          eyebrow="Primeiro passo"
          title="Crie seu clube"
          description="Escolha nome, sigla e escudo. Você começa com R$ 10,00 e um pacote fechado."
          actions={
            <Link
              to="/app"
              className="inline-flex min-h-11 items-center gap-2 text-sm text-muted-foreground"
            >
              <ArrowLeft size={17} aria-hidden="true" />
              Voltar
            </Link>
          }
        />

        <div className="grid gap-5 lg:grid-cols-[minmax(0,1fr)_18rem]">
          <form
            onSubmit={handleSubmit}
            className="space-y-5 rounded-lg border border-border bg-card p-4 sm:p-6"
            aria-busy={busy}
          >
            <div className="grid gap-4 sm:grid-cols-[minmax(0,1fr)_9rem]">
              <label htmlFor="club-name" className="block text-sm">
                <span className="mb-1.5 block text-xs font-semibold text-muted-foreground">
                  Nome do clube
                </span>
                <input
                  id="club-name"
                  value={name}
                  onChange={(e) => setName(e.target.value)}
                  className="min-h-12 w-full rounded-md border border-input bg-background px-3 py-2"
                  maxLength={24}
                  autoComplete="off"
                />
              </label>
              <label htmlFor="club-abbreviation" className="block text-sm">
                <span className="mb-1.5 block text-xs font-semibold text-muted-foreground">
                  Sigla
                </span>
                <input
                  id="club-abbreviation"
                  value={abbr}
                  onChange={(e) => setAbbr(e.target.value.toUpperCase())}
                  className="min-h-12 w-full rounded-md border border-input bg-background px-3 py-2 uppercase"
                  maxLength={4}
                  autoComplete="off"
                />
              </label>
            </div>
            <div>
              <div className="mb-3 flex items-center justify-between gap-3">
                <p className="text-xs font-semibold text-muted-foreground">Escolha o escudo</p>
                <span className="text-xs text-muted-foreground">
                  {badges.data?.length ?? 0} opções
                </span>
              </div>
              {badges.isLoading ? (
                <PageSkeleton rows={2} />
              ) : badges.error ? (
                <div
                  className="rounded-md border border-red-900/60 p-4 text-sm text-red-300"
                  role="alert"
                >
                  Não foi possível carregar os escudos.{" "}
                  <button type="button" className="underline" onClick={() => void badges.refetch()}>
                    Tentar novamente
                  </button>
                </div>
              ) : (
                <div
                  className="grid max-h-[22rem] grid-cols-4 gap-2 overflow-y-auto pr-1 sm:grid-cols-6 md:grid-cols-8"
                  role="group"
                  aria-label="Escudos disponíveis"
                >
                  {badges.data?.map((b) => (
                    <button
                      type="button"
                      key={b.code}
                      onClick={() => setBadgeCode(b.code)}
                      className={`relative min-h-16 rounded-md border p-1.5 transition-colors ${badgeCode === b.code ? "border-primary bg-primary/10" : "border-border bg-background hover:border-muted-foreground"}`}
                      aria-pressed={badgeCode === b.code}
                      aria-label={`Escudo ${b.label}`}
                    >
                      <img
                        src={b.asset_path}
                        alt=""
                        loading="lazy"
                        className="mx-auto h-12 w-12 object-contain"
                      />
                      {badgeCode === b.code && (
                        <span className="absolute right-1 top-1 grid size-4 place-items-center rounded-full bg-primary text-primary-foreground">
                          <Check size={11} aria-hidden="true" />
                        </span>
                      )}
                    </button>
                  ))}
                </div>
              )}
            </div>
            {error && (
              <p
                className="rounded-md border border-red-900/60 bg-red-950/20 p-3 text-sm text-red-300"
                role="alert"
              >
                {error}
              </p>
            )}
            <button
              type="submit"
              disabled={busy}
              className="min-h-12 w-full rounded-md bg-primary px-4 py-2 text-sm font-semibold text-primary-foreground active:scale-[.99] disabled:opacity-60 sm:w-auto"
            >
              {busy ? "Criando…" : "Confirmar clube"}
            </button>
          </form>
          <aside
            className="rounded-lg border border-border bg-card p-5 lg:sticky lg:top-6 lg:self-start"
            aria-live="polite"
          >
            <p className="text-xs font-semibold uppercase tracking-[0.1em] text-muted-foreground">
              Prévia
            </p>
            <div className="mt-5 grid justify-items-center text-center">
              <span className="grid size-28 place-items-center rounded-xl border border-border bg-background">
                {selectedBadge ? (
                  <img
                    src={selectedBadge.asset_path}
                    alt={`Escudo ${selectedBadge.label}`}
                    className="size-24 object-contain"
                  />
                ) : (
                  <Shield size={44} className="text-muted-foreground" aria-hidden="true" />
                )}
              </span>
              <strong className="mt-4 max-w-full truncate text-lg">
                {name.trim() || "Nome do clube"}
              </strong>
              <span className="mt-1 text-xs font-bold tracking-[0.14em] text-primary">
                {abbr.trim() || "SIGLA"}
              </span>
              <p className="mt-5 border-t border-border pt-4 text-xs leading-relaxed text-muted-foreground">
                Após criar, abra seu pacote inicial para receber as 10 cartas do elenco.
              </p>
            </div>
          </aside>
        </div>
      </div>
    </main>
  );
}

function createClubErrorMessage(error: unknown): string {
  const message = error instanceof Error ? error.message : String(error);
  if (/name.*(exists|unique)|club_name/i.test(message))
    return "Este nome de clube não está disponível.";
  if (/abbreviation.*(exists|unique)|club_abbreviation/i.test(message))
    return "Esta sigla não está disponível.";
  if (/badge.*(taken|unavailable|exists)/i.test(message))
    return "Este escudo não está mais disponível. Escolha outro.";
  if (/already.*club|owner.*unique/i.test(message)) return "Você já possui um clube.";
  return "Não foi possível criar o clube. Confira os dados e tente novamente.";
}
