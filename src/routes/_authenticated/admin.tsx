import { createFileRoute } from "@tanstack/react-router";
import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import { useServerFn } from "@tanstack/react-start";
import { useState } from "react";
import {
  adminListPendingUsers,
  adminResetUserPassword,
  adminSetUserStatus,
} from "@/lib/admin.functions";

export const Route = createFileRoute("/_authenticated/admin")({
  component: AdminPage,
});

function AdminPage() {
  const listFn = useServerFn(adminListPendingUsers);
  const statusFn = useServerFn(adminSetUserStatus);
  const resetFn = useServerFn(adminResetUserPassword);
  const qc = useQueryClient();

  const list = useQuery({ queryKey: ["admin", "users"], queryFn: () => listFn() });
  const [tempPassword, setTempPassword] = useState<{ username: string; password: string } | null>(
    null,
  );
  const [copyFeedback, setCopyFeedback] = useState<string | null>(null);

  const setStatus = useMutation({
    mutationFn: (v: { userId: string; status: "approved" | "blocked" | "pending" }) =>
      statusFn({ data: v }),
    onSuccess: () => qc.invalidateQueries({ queryKey: ["admin", "users"] }),
  });

  const reset = useMutation({
    mutationFn: (userId: string) => resetFn({ data: { userId } }),
    onMutate: () => {
      setTempPassword(null);
      setCopyFeedback(null);
    },
    onSuccess: (data) => setTempPassword({ username: data.username, password: data.tempPassword }),
  });

  async function copyPassword() {
    if (!tempPassword) return;
    await navigator.clipboard.writeText(tempPassword.password);
    setCopyFeedback("Senha copiada.");
  }

  function resetPasswordForUser(user: { id: string; username: string }) {
    if (!window.confirm(`Gerar senha temporária para ${user.username}?`)) return;
    reset.mutate(user.id);
  }

  if (list.isLoading) return <Shell>Carregando...</Shell>;
  if (list.error)
    return (
      <Shell>
        <p className="text-red-400">{adminErrorMessage(list.error)}</p>
      </Shell>
    );

  return (
    <Shell>
      <h1 className="text-xl font-bold">Painel administrativo</h1>
      <p className="mt-1 text-xs text-slate-500">
        Apenas admins. Ações registram log em admin_audit_logs.
      </p>

      <table className="mt-6 w-full text-sm">
        <thead className="border-b border-slate-800 text-left text-xs uppercase text-slate-500">
          <tr>
            <th className="py-2">Username</th>
            <th>Status</th>
            <th className="text-right">Ações</th>
          </tr>
        </thead>
        <tbody>
          {list.data?.map((u) => (
            <tr key={u.id} className="border-b border-slate-900">
              <td className="py-2">{u.username}</td>
              <td>{u.status}</td>
              <td className="space-x-2 text-right">
                {u.status !== "approved" && (
                  <button
                    onClick={() => setStatus.mutate({ userId: u.id, status: "approved" })}
                    disabled={setStatus.isPending || reset.isPending}
                    className="rounded-md border border-slate-700 px-2 py-1 text-xs disabled:opacity-60"
                  >
                    Aprovar
                  </button>
                )}
                {u.status !== "blocked" && (
                  <button
                    onClick={() => setStatus.mutate({ userId: u.id, status: "blocked" })}
                    disabled={setStatus.isPending || reset.isPending}
                    className="rounded-md border border-slate-700 px-2 py-1 text-xs disabled:opacity-60"
                  >
                    Bloquear
                  </button>
                )}
                <button
                  onClick={() => resetPasswordForUser(u)}
                  disabled={reset.isPending || setStatus.isPending}
                  className="rounded-md border border-slate-700 px-2 py-1 text-xs disabled:opacity-60"
                >
                  Gerar senha temporária
                </button>
              </td>
            </tr>
          ))}
        </tbody>
      </table>

      {reset.error && <p className="mt-4 text-sm text-red-400">{adminErrorMessage(reset.error)}</p>}

      {tempPassword && (
        <div className="mt-6 rounded-md border border-amber-700 bg-amber-950/40 p-3 text-sm">
          <p>
            Senha temporária gerada para <b>{tempPassword.username}</b>
          </p>
          <code className="mt-2 block font-mono text-base">{tempPassword.password}</code>
          <p className="mt-2 text-xs text-amber-200">
            Copie agora e envie ao usuário por canal seguro. A senha não será mostrada novamente.
          </p>
          <div className="mt-3 flex flex-wrap gap-2">
            <button
              type="button"
              onClick={copyPassword}
              className="rounded-md border border-amber-600 px-2 py-1 text-xs"
            >
              Copiar senha
            </button>
            <button
              type="button"
              onClick={() => {
                setTempPassword(null);
                setCopyFeedback(null);
              }}
              className="rounded-md border border-slate-700 px-2 py-1 text-xs"
            >
              Fechar
            </button>
          </div>
          {copyFeedback && <p className="mt-2 text-xs text-amber-100">{copyFeedback}</p>}
        </div>
      )}
    </Shell>
  );
}

function adminErrorMessage(error: unknown): string {
  const message = error instanceof Error ? error.message : String(error);
  const messages: Record<string, string> = {
    profile_not_approved: "Sua conta ainda não está aprovada para ações administrativas.",
    forbidden_not_admin: "Você não tem permissão de administrador.",
    target_profile_not_found: "Usuário alvo não encontrado no cadastro.",
    target_auth_user_not_found: "Usuário alvo não encontrado no Auth.",
    password_update_failed: "Não foi possível atualizar a senha.",
    password_update_missing_user: "A atualização não retornou o usuário alterado.",
  };
  const code = Object.keys(messages).find((key) => message.includes(key));
  return code ? messages[code] : "Não foi possível concluir. Tente novamente.";
}

function Shell({ children }: { children: React.ReactNode }) {
  return (
    <main className="min-h-screen bg-[#0b0f14] px-6 py-10 text-slate-100">
      <div className="mx-auto max-w-3xl">{children}</div>
    </main>
  );
}
