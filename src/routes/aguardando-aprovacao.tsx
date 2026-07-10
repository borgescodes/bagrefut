import { createFileRoute, Link } from "@tanstack/react-router";
import { Clock3, LogIn } from "lucide-react";
import { PublicShell } from "@/components/public-shell/PublicShell";

export const Route = createFileRoute("/aguardando-aprovacao")({
  component: WaitingPage,
  head: () => ({
    meta: [{ title: "Aguardando aprovação — BagreFut" }],
  }),
});

function WaitingPage() {
  return (
    <PublicShell>
      <div className="text-center">
        <span className="mx-auto grid size-12 place-items-center rounded-lg border border-amber-700/50 bg-amber-950/30 text-amber-300">
          <Clock3 aria-hidden="true" />
        </span>
        <p className="mt-5 text-xs font-semibold uppercase tracking-[0.12em] text-amber-300">
          Conta pendente
        </p>
        <h1 className="mt-2">Cadastro recebido</h1>
        <p className="mt-3 text-sm leading-relaxed text-muted-foreground">
          O administrador precisa aprovar sua conta. Depois da liberação, entre novamente para criar
          seu clube.
        </p>
        <p className="mt-4 rounded-md border border-border bg-background p-3 text-xs leading-relaxed text-muted-foreground">
          Próximo passo: aguarde a confirmação do administrador e tente acessar novamente.
        </p>
        <p className="mt-6 text-sm">
          <Link
            to="/login"
            className="inline-flex min-h-12 w-full items-center justify-center gap-2 rounded-md bg-primary px-4 font-semibold text-primary-foreground"
          >
            <LogIn size={18} aria-hidden="true" />
            Ir para o login
          </Link>
        </p>
      </div>
    </PublicShell>
  );
}
