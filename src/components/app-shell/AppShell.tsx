import { useQuery } from "@tanstack/react-query";
import { Link, useLocation, useNavigate } from "@tanstack/react-router";
import { useServerFn } from "@tanstack/react-start";
import {
  CircleUserRound,
  Home,
  LayoutGrid,
  LogOut,
  Menu,
  PackageOpen,
  ShieldCheck,
  ShoppingBag,
  Trophy,
  UsersRound,
} from "lucide-react";
import type { ReactNode } from "react";
import { centsToReal } from "@/domain/rules/validators";
import { getMe, getMyClub } from "@/lib/game.functions";
import { supabase } from "@/integrations/supabase/client";
import { BrandMark } from "@/components/brand/BrandMark";
import {
  Sheet,
  SheetClose,
  SheetContent,
  SheetDescription,
  SheetHeader,
  SheetTitle,
  SheetTrigger,
} from "@/components/ui/sheet";
import { Skeleton } from "@/components/ui/skeleton";

const primaryItems = [
  { to: "/app", label: "Início", icon: Home },
  { to: "/elenco", label: "Elenco", icon: UsersRound },
  { to: "/mercado", label: "Mercado", icon: ShoppingBag },
  { to: "/classificacao", label: "Tabela", icon: Trophy },
] as const;

export function AppShell({ children }: { children: ReactNode }) {
  const location = useLocation();
  const navigate = useNavigate();
  const meFn = useServerFn(getMe);
  const clubFn = useServerFn(getMyClub);
  const me = useQuery({ queryKey: ["appShell", "me"], queryFn: () => meFn(), staleTime: 30_000 });
  const club = useQuery({
    queryKey: ["appShell", "myClub"],
    queryFn: () => clubFn(),
    staleTime: 30_000,
  });
  const isAdmin = me.data?.roles.includes("admin") ?? false;

  async function signOut() {
    await supabase.auth.signOut();
    await navigate({ to: "/login" });
  }

  return (
    <div className="app-shell">
      <header className="app-mobile-header">
        <ClubIdentity
          name={club.data?.name}
          abbreviation={club.data?.abbreviation}
          loading={club.isLoading}
        />
        <BalanceDisplay balance={club.data?.balance_cents} loading={club.isLoading} />
      </header>

      <aside className="app-sidebar" aria-label="Navegação principal">
        <BrandMark />
        <div className="app-sidebar__club">
          <ClubIdentity
            name={club.data?.name}
            abbreviation={club.data?.abbreviation}
            loading={club.isLoading}
          />
          <BalanceDisplay balance={club.data?.balance_cents} loading={club.isLoading} />
        </div>
        <nav className="app-sidebar__nav">
          {primaryItems.map((item) => (
            <NavItem key={item.to} {...item} active={isActive(location.pathname, item.to)} />
          ))}
          <NavItem
            to="/abrir-pacote"
            label="Abrir pacote"
            icon={PackageOpen}
            active={isActive(location.pathname, "/abrir-pacote")}
          />
          {isAdmin && (
            <NavItem
              to="/admin"
              label="Administração"
              icon={ShieldCheck}
              active={isActive(location.pathname, "/admin")}
            />
          )}
        </nav>
        <button type="button" className="app-sidebar__logout" onClick={() => void signOut()}>
          <LogOut size={18} aria-hidden="true" />
          Sair
        </button>
      </aside>

      <div className="app-content">{children}</div>

      <nav className="app-bottom-nav" aria-label="Navegação principal">
        {primaryItems.map((item) => (
          <NavItem key={item.to} {...item} active={isActive(location.pathname, item.to)} compact />
        ))}
        <MoreMenu isAdmin={isAdmin} hasClub={Boolean(club.data)} onSignOut={signOut} />
      </nav>
    </div>
  );
}

function NavItem({
  to,
  label,
  icon: Icon,
  active,
  compact = false,
}: {
  to: "/app" | "/elenco" | "/mercado" | "/classificacao" | "/abrir-pacote" | "/admin";
  label: string;
  icon: typeof Home;
  active: boolean;
  compact?: boolean;
}) {
  return (
    <Link
      to={to}
      className={compact ? "app-bottom-nav__item" : "app-sidebar__item"}
      data-active={active || undefined}
      aria-current={active ? "page" : undefined}
    >
      <Icon size={compact ? 20 : 18} strokeWidth={active ? 2.4 : 1.9} aria-hidden="true" />
      <span>{label}</span>
    </Link>
  );
}

function MoreMenu({
  isAdmin,
  hasClub,
  onSignOut,
}: {
  isAdmin: boolean;
  hasClub: boolean;
  onSignOut: () => Promise<void>;
}) {
  return (
    <Sheet>
      <SheetTrigger asChild>
        <button type="button" className="app-bottom-nav__item" aria-label="Abrir mais opções">
          <Menu size={20} aria-hidden="true" />
          <span>Mais</span>
        </button>
      </SheetTrigger>
      <SheetContent side="bottom" className="app-more-sheet">
        <SheetHeader className="text-left">
          <SheetTitle>Mais opções</SheetTitle>
          <SheetDescription>Acesse sua conta e os outros recursos do clube.</SheetDescription>
        </SheetHeader>
        <div className="app-more-sheet__links">
          <SheetMenuLink to="/abrir-pacote" icon={PackageOpen} label="Abrir pacote" />
          <SheetMenuLink
            to={hasClub ? "/app" : "/criar-clube"}
            icon={hasClub ? CircleUserRound : LayoutGrid}
            label={hasClub ? "Visualizar clube" : "Criar clube"}
          />
          {isAdmin && <SheetMenuLink to="/admin" icon={ShieldCheck} label="Administração" />}
          <SheetClose asChild>
            <button
              type="button"
              className="app-more-sheet__danger"
              onClick={() => void onSignOut()}
            >
              <LogOut size={19} aria-hidden="true" />
              Sair
            </button>
          </SheetClose>
        </div>
      </SheetContent>
    </Sheet>
  );
}

function SheetMenuLink({
  to,
  icon: Icon,
  label,
}: {
  to: "/abrir-pacote" | "/app" | "/criar-clube" | "/admin";
  icon: typeof Home;
  label: string;
}) {
  return (
    <SheetClose asChild>
      <Link to={to} className="app-more-sheet__link">
        <Icon size={19} aria-hidden="true" />
        {label}
      </Link>
    </SheetClose>
  );
}

export function ClubIdentity({
  name,
  abbreviation,
  loading = false,
}: {
  name?: string;
  abbreviation?: string;
  loading?: boolean;
}) {
  if (loading) return <Skeleton className="h-10 w-36" />;
  return (
    <div className="club-identity">
      <span className="club-identity__badge" aria-hidden="true">
        {abbreviation?.slice(0, 3) ?? "BF"}
      </span>
      <span className="club-identity__copy">
        <span className="club-identity__eyebrow">Meu clube</span>
        <strong>{name ?? "BagreFut"}</strong>
      </span>
    </div>
  );
}

export function BalanceDisplay({
  balance,
  loading = false,
}: {
  balance?: number;
  loading?: boolean;
}) {
  if (loading) return <Skeleton className="h-9 w-20" />;
  return (
    <div className="balance-display">
      <span>Saldo</span>
      <strong className="tabular-nums">{centsToReal(balance ?? 0)}</strong>
    </div>
  );
}

function isActive(pathname: string, to: string) {
  return pathname === to || pathname.startsWith(`${to}/`);
}
