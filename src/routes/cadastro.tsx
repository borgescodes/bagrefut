import { createFileRoute, Link, useNavigate } from "@tanstack/react-router";
import { useState } from "react";
import { supabase } from "@/integrations/supabase/client";
import {
  usernameToInternalEmail,
  validatePassword,
  validateUsername,
} from "@/domain/rules/validators";

export const Route = createFileRoute("/cadastro")({
  component: CadastroPage,
  head: () => ({
    meta: [
      { title: "Cadastro — BagreFut" },
      { name: "description", content: "Crie sua conta no BagreFut. Aprovação manual pelo admin." },
    ],
  }),
});

function CadastroPage() {
  const nav = useNavigate();
  const [username, setUsername] = useState("");
  const [password, setPassword] = useState("");
  const [error, setError] = useState<string | null>(null);
  const [busy, setBusy] = useState(false);

  async function handleSubmit(e: React.FormEvent) {
    e.preventDefault();
    setError(null);
    const u = validateUsername(username);
    if (!u.ok) return setError(u.error);
    const p = validatePassword(password);
    if (!p.ok) return setError(p.error);

    setBusy(true);
    const { error } = await supabase.auth.signUp({
      email: usernameToInternalEmail(username),
      password,
      options: { data: { username } },
    });
    setBusy(false);
    if (error) return setError(error.message);
    await supabase.auth.signOut();
    nav({ to: "/aguardando-aprovacao" });
  }

  return (
    <main className="min-h-screen bg-[#0b0f14] px-6 py-12 text-slate-100">
      <div className="mx-auto max-w-md">
        <h1 className="text-2xl font-semibold">Cadastro</h1>
        <p className="mt-2 text-sm text-slate-400">
          Escolha um nome único (3-16, letras e números). Aprovação é manual.
        </p>
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
            <span className="mb-1 block">Senha (mín. 8, com letra e número)</span>
            <input
              type="password"
              value={password}
              onChange={(e) => setPassword(e.target.value)}
              className="w-full rounded-md border border-slate-700 bg-slate-900 px-3 py-2 text-sm"
              autoComplete="new-password"
              required
            />
          </label>
          {error && <p className="text-sm text-red-400">{error}</p>}
          <button
            type="submit"
            disabled={busy}
            className="w-full rounded-md bg-slate-100 px-4 py-2 text-sm font-medium text-slate-900 disabled:opacity-60"
          >
            {busy ? "Enviando..." : "Cadastrar"}
          </button>
        </form>
        <p className="mt-4 text-sm">
          <Link to="/login" className="underline">Já tem conta? Entrar</Link>
        </p>
      </div>
    </main>
  );
}
