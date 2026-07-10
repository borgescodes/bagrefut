import { createFileRoute, useNavigate } from "@tanstack/react-router";
import { useServerFn } from "@tanstack/react-start";
import { useState } from "react";
import { Eye, EyeOff, KeyRound } from "lucide-react";
import { changeTemporaryPassword } from "@/lib/auth.functions";
import { supabase } from "@/integrations/supabase/client";
import { validatePassword, validatePasswordConfirmation } from "@/domain/rules/validators";
import { PublicShell } from "@/components/public-shell/PublicShell";

export const Route = createFileRoute("/_authenticated/trocar-senha")({
  component: ChangeTemporaryPasswordPage,
});

function ChangeTemporaryPasswordPage() {
  const nav = useNavigate();
  const changePasswordFn = useServerFn(changeTemporaryPassword);
  const [newPassword, setNewPassword] = useState("");
  const [confirmation, setConfirmation] = useState("");
  const [error, setError] = useState<string | null>(null);
  const [busy, setBusy] = useState(false);
  const [showPassword, setShowPassword] = useState(false);

  async function handleSubmit(e: React.FormEvent) {
    e.preventDefault();
    if (busy) return;
    setError(null);
    const passwordValidation = validatePassword(newPassword);
    if (!passwordValidation.ok)
      return setError(changePasswordErrorMessage(passwordValidation.error));
    const confirmationValidation = validatePasswordConfirmation(newPassword, confirmation);
    if (!confirmationValidation.ok)
      return setError(changePasswordErrorMessage(confirmationValidation.error));
    setBusy(true);
    try {
      await changePasswordFn({ data: { newPassword, confirmation } });
      await supabase.auth.signOut();
      window.sessionStorage.setItem("bagrefut_password_changed", "1");
      await nav({ to: "/login" });
    } catch (err) {
      setError(changePasswordErrorMessage(err));
    } finally {
      setBusy(false);
    }
  }

  return (
    <PublicShell>
      <span className="mb-4 grid size-11 place-items-center rounded-lg border border-border bg-background text-primary">
        <KeyRound aria-hidden="true" />
      </span>
      <p className="text-xs font-semibold uppercase tracking-[0.12em] text-primary">
        Acesso protegido
      </p>
      <h1 className="mt-2">Defina uma nova senha</h1>
      <p className="mt-2 text-sm leading-relaxed text-muted-foreground">
        Esta senha temporária precisa ser substituída antes de acessar o jogo.
      </p>
      <form onSubmit={handleSubmit} className="mt-6 space-y-4">
        <label htmlFor="new-password" className="block text-sm">
          <span className="mb-1 block">Nova senha</span>
          <span className="relative block">
            <input
              id="new-password"
              type={showPassword ? "text" : "password"}
              value={newPassword}
              onChange={(e) => setNewPassword(e.target.value)}
              className="w-full rounded-md border px-3 py-2 pr-12 text-sm"
              autoComplete="new-password"
              aria-describedby="password-requirements"
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
          <span id="password-requirements" className="mt-1.5 block text-xs text-muted-foreground">
            8 a 32 caracteres, com pelo menos uma letra e um número.
          </span>
        </label>
        <label htmlFor="password-confirmation" className="block text-sm">
          <span className="mb-1 block">Confirmar nova senha</span>
          <input
            id="password-confirmation"
            type={showPassword ? "text" : "password"}
            value={confirmation}
            onChange={(e) => setConfirmation(e.target.value)}
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
          className="min-h-12 w-full rounded-md bg-primary px-4 py-2 text-sm font-semibold text-primary-foreground active:scale-[.98] disabled:opacity-60"
          aria-busy={busy}
        >
          {busy ? "Alterando…" : "Alterar senha"}
        </button>
      </form>
    </PublicShell>
  );
}

function changePasswordErrorMessage(error: unknown): string {
  const message = error instanceof Error ? error.message : String(error);
  const messages: Record<string, string> = {
    temporary_password_change_not_required: "Esta conta não exige troca de senha temporária.",
    password_confirmation_mismatch: "As senhas não conferem.",
    password_length: "A senha deve ter entre 8 e 32 caracteres.",
    password_missing_letter: "A senha deve ter pelo menos uma letra.",
    password_missing_number: "A senha deve ter pelo menos um número.",
    password_update_failed: "Não foi possível atualizar a senha.",
  };
  const code = Object.keys(messages).find((key) => message.includes(key));
  return code ? messages[code] : "Não foi possível concluir. Tente novamente.";
}
