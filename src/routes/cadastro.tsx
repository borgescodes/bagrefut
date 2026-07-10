import { createFileRoute, Link, useNavigate } from "@tanstack/react-router";
import { useState } from "react";
import { Eye, EyeOff, UserPlus } from "lucide-react";
import { mapAuthErrorMessage } from "@/domain/rules/auth";
import {
  usernameToInternalEmail,
  validatePassword,
  validatePasswordConfirmation,
  validateUsername,
} from "@/domain/rules/validators";
import { supabase } from "@/integrations/supabase/client";
import { PublicShell } from "@/components/public-shell/PublicShell";

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
  const [passwordConfirmation, setPasswordConfirmation] = useState("");
  const [error, setError] = useState<string | null>(null);
  const [busy, setBusy] = useState(false);
  const [showPassword, setShowPassword] = useState(false);

  async function handleSubmit(e: React.FormEvent) {
    e.preventDefault();
    if (busy) return;
    setError(null);
    const u = validateUsername(username);
    if (!u.ok) return setError(validationMessage(u.error));
    const p = validatePassword(password);
    if (!p.ok) return setError(validationMessage(p.error));
    const pc = validatePasswordConfirmation(password, passwordConfirmation);
    if (!pc.ok) return setError(validationMessage(pc.error));

    setBusy(true);
    const { error } = await supabase.auth.signUp({
      email: usernameToInternalEmail(username),
      password,
      options: { data: { username } },
    });
    setBusy(false);
    if (error) return setError(mapAuthErrorMessage(error.message));
    await supabase.auth.signOut();
    nav({ to: "/aguardando-aprovacao" });
  }

  return (
    <PublicShell>
      <p className="text-xs font-semibold uppercase tracking-[0.12em] text-primary">Novo técnico</p>
      <h1 className="mt-2">Crie sua conta</h1>
      <p className="mt-2 text-sm leading-relaxed text-muted-foreground">
        Use de 3 a 16 letras e números. O acesso é liberado após aprovação do administrador.
      </p>
      <form onSubmit={handleSubmit} className="mt-6 space-y-4">
        <label htmlFor="signup-username" className="block text-sm">
          <span className="mb-1 block">Nome de usuário</span>
          <input
            id="signup-username"
            value={username}
            onChange={(e) => setUsername(e.target.value)}
            className="w-full rounded-md border px-3 py-2 text-sm"
            autoComplete="username"
            autoCapitalize="none"
            spellCheck={false}
            required
          />
        </label>
        <label htmlFor="signup-password" className="block text-sm">
          <span className="mb-1 block">Senha</span>
          <span className="relative block">
            <input
              id="signup-password"
              type={showPassword ? "text" : "password"}
              value={password}
              onChange={(e) => setPassword(e.target.value)}
              className="w-full rounded-md border px-3 py-2 pr-12 text-sm"
              autoComplete="new-password"
              aria-describedby="signup-password-help"
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
          <span id="signup-password-help" className="mt-1.5 block text-xs text-muted-foreground">
            8 a 32 caracteres, com pelo menos uma letra e um número.
          </span>
        </label>
        <label htmlFor="signup-confirmation" className="block text-sm">
          <span className="mb-1 block">Confirmar senha</span>
          <input
            id="signup-confirmation"
            type={showPassword ? "text" : "password"}
            value={passwordConfirmation}
            onChange={(e) => setPasswordConfirmation(e.target.value)}
            className="w-full rounded-md border px-3 py-2 text-sm"
            autoComplete="new-password"
            required
          />
        </label>
        {error && (
          <p className="text-sm text-red-400" role="alert">
            {error}
          </p>
        )}
        <button
          type="submit"
          disabled={busy}
          className="inline-flex min-h-12 w-full items-center justify-center gap-2 rounded-md bg-primary px-4 py-2 text-sm font-semibold text-primary-foreground active:scale-[.98] disabled:opacity-60"
          aria-busy={busy}
        >
          <UserPlus size={18} aria-hidden="true" />
          {busy ? "Enviando…" : "Criar conta"}
        </button>
      </form>
      <p className="mt-5 text-sm text-muted-foreground">
        <Link
          to="/login"
          className="font-medium text-primary underline decoration-primary/30 underline-offset-4"
        >
          Já tem conta? Entrar
        </Link>
      </p>
    </PublicShell>
  );
}

function validationMessage(code: string): string {
  const messages: Record<string, string> = {
    username_required: "Informe um nome de usuário.",
    username_invalid_format: "Use 3 a 16 letras e números no nome de usuário.",
    password_required: "Informe uma senha.",
    password_length: "A senha deve ter entre 8 e 32 caracteres.",
    password_missing_letter: "A senha deve ter pelo menos uma letra.",
    password_missing_number: "A senha deve ter pelo menos um número.",
    password_confirmation_required: "Confirme sua senha.",
    password_confirmation_mismatch: "As senhas não conferem.",
  };
  return messages[code] ?? "Não foi possível concluir. Tente novamente.";
}
