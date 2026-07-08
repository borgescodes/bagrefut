import { createFileRoute, useNavigate } from "@tanstack/react-router";
import { useServerFn } from "@tanstack/react-start";
import { useState } from "react";
import { changeTemporaryPassword } from "@/lib/auth.functions";
import { supabase } from "@/integrations/supabase/client";

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

  async function handleSubmit(e: React.FormEvent) {
    e.preventDefault();
    setError(null);
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
    <main className="min-h-screen bg-[#0b0f14] px-6 py-12 text-slate-100">
      <div className="mx-auto max-w-md">
        <h1 className="text-2xl font-semibold">Trocar senha</h1>
        <p className="mt-2 text-sm text-slate-400">
          Defina uma nova senha para continuar. Depois disso, entre novamente.
        </p>
        <form onSubmit={handleSubmit} className="mt-6 space-y-4">
          <label className="block text-sm">
            <span className="mb-1 block">Nova senha</span>
            <input
              type="password"
              value={newPassword}
              onChange={(e) => setNewPassword(e.target.value)}
              className="w-full rounded-md border border-slate-700 bg-slate-900 px-3 py-2 text-sm"
              autoComplete="new-password"
              required
            />
          </label>
          <label className="block text-sm">
            <span className="mb-1 block">Confirmar nova senha</span>
            <input
              type="password"
              value={confirmation}
              onChange={(e) => setConfirmation(e.target.value)}
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
            {busy ? "Alterando..." : "Alterar senha"}
          </button>
        </form>
      </div>
    </main>
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
