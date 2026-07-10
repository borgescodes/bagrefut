import { Link } from "@tanstack/react-router";
import type { ReactNode } from "react";
import { BrandMark } from "@/components/brand/BrandMark";
import { cn } from "@/lib/utils";

export function PublicShell({
  children,
  compact = false,
}: {
  children: ReactNode;
  compact?: boolean;
}) {
  return (
    <main className={cn("public-shell", compact && "public-shell--compact")}>
      <div className="public-shell__frame">
        <Link to="/" className="public-shell__brand">
          <BrandMark />
        </Link>
        <div className="public-shell__content">{children}</div>
        <p className="public-shell__footer">BagreFut · PGM joga aqui</p>
      </div>
    </main>
  );
}
