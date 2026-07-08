import { createFileRoute, Outlet, redirect } from "@tanstack/react-router";
import { supabase } from "@/integrations/supabase/client";

export const Route = createFileRoute("/_authenticated")({
  ssr: false,
  beforeLoad: async ({ location }) => {
    const { data, error } = await supabase.auth.getUser();
    if (error || !data.user) throw redirect({ to: "/login" });
    if (
      data.user.app_metadata?.must_change_password === true &&
      location.pathname !== "/trocar-senha"
    ) {
      throw redirect({ to: "/trocar-senha" });
    }
    return { user: data.user };
  },
  component: () => <Outlet />,
});
