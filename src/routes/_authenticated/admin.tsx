import { createFileRoute } from "@tanstack/react-router";
import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import { useServerFn } from "@tanstack/react-start";
import {
  adminListPendingUsers,
  adminResetUserPassword,
  adminSetUserStatus,
} from "@/lib/admin.functions";
import { useState } from "react";

export const Route = createFileRoute("/_authenticated/admin")({
  component: AdminPage,
});

function AdminPage() {
  const listFn = useServerFn(adminListPendingUsers);
  const statusFn = useServerFn(adminSetUserStatus);
  const resetFn = useServerFn(adminResetUserPassword);
  const qc = useQueryClient();

  const list = useQuery({ queryKey: ["admin", "users"], queryFn: () => listFn() });
  const [tempPassword, setTempPassword] = useState<{ userId: string; pw: string } | null>(null);

  const setStatus = useMutation({
    mutationFn: (v: { userId: string; status: "approved" | "blocked" | "pending" }) =>
      statusFn({ data: v }),
    onSuccess: () => qc.invalidateQueries({ queryKey: ["admin", "users"] }),
  });

  const reset = useMutation({
    mutationFn: (userId: string) => resetFn({ data: { userId } }),
    onSuccess: (data, userId) => setTempPassword({ userId, pw: data.tempPassword }),
  });

  if (list.isLoading) return <Shell>Carregando…</Shell>;
  if (list.error) return <Shell><p className="text-red-400">{String(list.error)}</p></Shell>;

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
                    className="rounded-md border border-slate-700 px-2 py-1 text-xs"
                  >Aprovar</button>
                )}
                {u.status !== "blocked" && (
                  <button
                    onClick={() => setStatus.mutate({ userId: u.id, status: "blocked" })}
                    className="rounded-md border border-slate-700 px-2 py-1 text-xs"
                  >Bloquear</button>
                )}
                <button
                  onClick={() => reset.mutate(u.id)}
                  className="rounded-md border border-slate-700 px-2 py-1 text-xs"
                >Nova senha</button>
              </td>
            </tr>
          ))}
        </tbody>
      </table>

      {tempPassword && (
        <div className="mt-6 rounded-md border border-amber-700 bg-amber-950/40 p-3 text-sm">
          Senha temporária para <b>{tempPassword.userId.slice(0, 8)}…</b>:{" "}
          <code className="font-mono">{tempPassword.pw}</code>
          <p className="mt-1 text-xs text-amber-200">Informe ao usuário por canal seguro. Não será mostrada de novo.</p>
        </div>
      )}
    </Shell>
  );
}

function Shell({ children }: { children: React.ReactNode }) {
  return (
    <main className="min-h-screen bg-[#0b0f14] px-6 py-10 text-slate-100">
      <div className="mx-auto max-w-3xl">{children}</div>
    </main>
  );
}
