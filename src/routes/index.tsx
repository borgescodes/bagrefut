import { createFileRoute, Link } from "@tanstack/react-router";

export const Route = createFileRoute("/")({
  component: LandingPage,
  head: () => ({
    meta: [
      { title: "BagreFut" },
      {
        name: "description",
        content:
          "BagreFut é o jogo de gestão de clube dos amigos: 6 times, 10 rodadas, decisões diárias às 22h.",
      },
    ],
  }),
});

function LandingPage() {
  return (
    <main className="min-h-screen bg-[#0b0f14] px-6 py-12 text-slate-100">
      <div className="mx-auto max-w-3xl">
        <h1 className="text-4xl font-bold tracking-tight">BagreFut</h1>
        <p className="mt-2 text-lg text-slate-300">
          Monte clube. Gerencie elenco. Domine PGM.
        </p>
        <p className="mt-6 text-sm text-slate-400">
          Fundação técnica — sem UI final. Use as telas técnicas abaixo para operar o backend.
        </p>
        <div className="mt-8 flex flex-wrap gap-3">
          <Link
            to="/cadastro"
            className="rounded-md bg-slate-100 px-4 py-2 text-sm font-medium text-slate-900"
          >
            Cadastro
          </Link>
          <Link
            to="/login"
            className="rounded-md border border-slate-700 px-4 py-2 text-sm font-medium"
          >
            Login
          </Link>
          <Link
            to="/app"
            className="rounded-md border border-slate-700 px-4 py-2 text-sm font-medium"
          >
            Área do usuário
          </Link>
        </div>
      </div>
    </main>
  );
}
