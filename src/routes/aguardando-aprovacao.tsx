import { createFileRoute, Link } from "@tanstack/react-router";

export const Route = createFileRoute("/aguardando-aprovacao")({
  component: WaitingPage,
  head: () => ({
    meta: [{ title: "Aguardando aprovação — BagreFut" }],
  }),
});

function WaitingPage() {
  return (
    <main className="min-h-screen bg-[#0b0f14] px-6 py-12 text-slate-100">
      <div className="mx-auto max-w-md text-center">
        <h1 className="text-2xl font-semibold">Cadastro recebido</h1>
        <p className="mt-4 text-sm text-slate-300">
          Sua conta está aguardando aprovação do administrador. Você poderá entrar assim que for
          liberada.
        </p>
        <p className="mt-6 text-sm">
          <Link to="/login" className="underline">
            Voltar ao login
          </Link>
        </p>
      </div>
    </main>
  );
}
