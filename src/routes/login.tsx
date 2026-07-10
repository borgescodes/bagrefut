import { createFileRoute, Link, useNavigate } from "@tanstack/react-router";
import { useState } from "react";
import { Eye, EyeOff, LogIn } from "lucide-react";
import { buildPasswordRecoveryWhatsAppUrl, mapAuthErrorMessage } from "@/domain/rules/auth";
import { usernameToInternalEmail } from "@/domain/rules/validators";
import { supabase } from "@/integrations/supabase/client";
import { PublicShell } from "@/components/public-shell/PublicShell";

export const Route = createFileRoute("/login")({
  component: LoginPage,
  head: () => ({
    meta: [{ title: "Login — BagreFut" }, { name: "description", content: "Entre no BagreFut." }],
  }),
});

function LoginPage() {
  const nav = useNavigate();
  const [username, setUsername] = useState("");
  const [password, setPassword] = useState("");
  const [error, setError] = useState<string | null>(null);
  const [success, setSuccess] = useState(() => {
    if (typeof window === "undefined") return false;
    const passwordChanged = window.sessionStorage.getItem("bagrefut_password_changed") === "1";
    window.sessionStorage.removeItem("bagrefut_password_changed");
    return passwordChanged;
  });
  const [busy, setBusy] = useState(false);
  const [showPassword, setShowPassword] = useState(false);

  async function handleSubmit(e: React.FormEvent) {
    e.preventDefault();
    if (busy) return;
    setError(null);
    setSuccess(false);
    setBusy(true);
    const { data, error } = await supabase.auth.signInWithPassword({
      email: usernameToInternalEmail(username),
      password,
    });
    setBusy(false);
    if (error) return setError(mapAuthErrorMessage(error.message));
    nav({ to: data.user?.app_metadata?.must_change_password === true ? "/trocar-senha" : "/app" });
  }

  return (
    <PublicShell>
      <p className="text-xs font-semibold uppercase tracking-[0.12em] text-primary">Bem-vindo</p>
      <h1 className="mt-2">Entre no seu clube</h1>
      <p className="mt-2 text-sm leading-relaxed text-muted-foreground">
        Continue sua temporada, ajuste a escalação e acompanhe o mercado.
      </p>
      {success && (
        <p
          className="mt-4 rounded-md border border-emerald-800/60 bg-emerald-950/30 p-3 text-sm text-emerald-300"
          aria-live="polite"
        >
          Senha alterada. Entre novamente.
        </p>
      )}
      <form onSubmit={handleSubmit} className="mt-6 space-y-4">
        <label htmlFor="login-username" className="block text-sm">
          <span className="mb-1 block">Nome de usuário</span>
          <input
            id="login-username"
            value={username}
            onChange={(e) => setUsername(e.target.value)}
            className="w-full rounded-md border px-3 py-2 text-sm"
            autoComplete="username"
            autoCapitalize="none"
            spellCheck={false}
            enterKeyHint="next"
            required
          />
        </label>
        <label htmlFor="login-password" className="block text-sm">
          <span className="mb-1 block">Senha</span>
          <span className="relative block">
            <input
              id="login-password"
              type={showPassword ? "text" : "password"}
              value={password}
              onChange={(e) => setPassword(e.target.value)}
              className="w-full rounded-md border px-3 py-2 pr-12 text-sm"
              autoComplete="current-password"
              required
            />
            <button
              type="button"
              onClick={() => setShowPassword((value) => !value)}
              className="absolute inset-y-0 right-0 grid w-12 place-items-center text-muted-foreground"
              aria-label={showPassword ? "Ocultar senha" : "Mostrar senha"}
            >
              {showPassword ? (
                <EyeOff size={18} aria-hidden="true" />
              ) : (
                <Eye size={18} aria-hidden="true" />
              )}
            </button>
          </span>
        </label>
        {error && (
          <p className="text-sm text-red-400" role="alert">
            {error}
          </p>
        )}
        <button
          type="submit"
          disabled={busy}
          className="inline-flex min-h-12 w-full items-center justify-center gap-2 rounded-md bg-primary px-4 py-2 text-sm font-semibold text-primary-foreground transition-transform active:scale-[.98] disabled:opacity-60"
          aria-busy={busy}
        >
          <LogIn size={18} aria-hidden="true" />
          {busy ? "Entrando…" : "Entrar"}
        </button>
      </form>
      <div className="mt-5 flex flex-col gap-3 text-sm">
        <a
          href={buildPasswordRecoveryWhatsAppUrl(username)}
          target="_blank"
          rel="noopener noreferrer"
          className="text-muted-foreground underline decoration-border underline-offset-4 hover:text-foreground"
        >
          Esqueci minha senha
        </a>
        <Link
          to="/cadastro"
          className="font-medium text-primary underline decoration-primary/30 underline-offset-4"
        >
          Não tem conta? Cadastre-se
        </Link>
      </div>
    </PublicShell>
  );
}
