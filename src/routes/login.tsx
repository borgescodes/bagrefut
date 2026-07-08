import { createFileRoute, Link, useNavigate } from "@tanstack/react-router";
import { useState } from "react";
import { buildPasswordRecoveryWhatsAppUrl, mapAuthErrorMessage } from "@/domain/rules/auth";
import { usernameToInternalEmail } from "@/domain/rules/validators";
import { supabase } from "@/integrations/supabase/client";

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

  async function handleSubmit(e: React.FormEvent) {
    e.preventDefault();
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
    <main className="min-h-screen bg-[#0b0f14] px-6 py-12 text-slate-100">
      <div className="mx-auto max-w-md">
        <h1 className="text-2xl font-semibold">Entrar</h1>
        {success && (
          <p className="mt-4 text-sm text-emerald-300">Senha alterada. Entre novamente.</p>
        )}
        <form onSubmit={handleSubmit} className="mt-6 space-y-4">
          <label className="block text-sm">
            <span className="mb-1 block">Nome de usuário</span>
            <input
              value={username}
              onChange={(e) => setUsername(e.target.value)}
              className="w-full rounded-md border border-slate-700 bg-slate-900 px-3 py-2 text-sm"
              autoComplete="username"
              required
            />
          </label>
          <label className="block text-sm">
            <span className="mb-1 block">Senha</span>
            <input
              type="password"
              value={password}
              onChange={(e) => setPassword(e.target.value)}
              className="w-full rounded-md border border-slate-700 bg-slate-900 px-3 py-2 text-sm"
              autoComplete="current-password"
              required
            />
          </label>
          {error && <p className="text-sm text-red-400">{error}</p>}
          <button
            type="submit"
            disabled={busy}
            className="w-full rounded-md bg-slate-100 px-4 py-2 text-sm font-medium text-slate-900 disabled:opacity-60"
          >
            {busy ? "Entrando..." : "Entrar"}
          </button>
        </form>
        <div className="mt-4 space-y-2 text-sm">
          <a
            href={buildPasswordRecoveryWhatsAppUrl(username)}
            target="_blank"
            rel="noopener noreferrer"
            className="block underline"
          >
            Esqueci minha senha
          </a>
          <Link to="/cadastro" className="underline">
            Não tem conta? Cadastre-se
          </Link>
        </div>
      </div>
    </main>
  );
}
