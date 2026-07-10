import { Trophy } from "lucide-react";
import { cn } from "@/lib/utils";

export function BrandMark({
  compact = false,
  className,
}: {
  compact?: boolean;
  className?: string;
}) {
  return (
    <span className={cn("brand-mark", className)} aria-label="BagreFut">
      <span className="brand-mark__icon" aria-hidden="true">
        <Trophy size={compact ? 16 : 18} strokeWidth={2.4} />
      </span>
      {!compact && <span>BagreFut</span>}
    </span>
  );
}
