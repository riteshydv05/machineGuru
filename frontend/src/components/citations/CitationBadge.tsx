import { useState, useRef, useEffect } from "react";
import type { SourceReference } from "@/types";
import { SourcePreview } from "./SourcePreview";

interface Props {
  index: number;
  source: SourceReference;
  isActive?: boolean;
  onClick?: () => void;
}

export function CitationBadge({ index, source, isActive, onClick }: Props) {
  const [open, setOpen] = useState(false);
  const ref = useRef<HTMLSpanElement>(null);
  const timeoutRef = useRef<number | undefined>(undefined);

  useEffect(() => {
    return () => clearTimeout(timeoutRef.current);
  }, []);

  const handleMouseEnter = () => {
    clearTimeout(timeoutRef.current);
    timeoutRef.current = window.setTimeout(() => setOpen(true), 200);
  };

  const handleMouseLeave = () => {
    clearTimeout(timeoutRef.current);
    timeoutRef.current = window.setTimeout(() => setOpen(false), 300);
  };

  return (
    <span className="relative inline-group" ref={ref}>
      <sup
        role="button"
        tabIndex={0}
        onMouseEnter={handleMouseEnter}
        onMouseLeave={handleMouseLeave}
        onClick={onClick}
        onKeyDown={(e) => { if (e.key === "Enter" || e.key === " ") onClick?.(); }}
        className={`
          inline-flex items-center justify-center
          min-w-[1.25rem] h-4 px-1
          text-[10px] font-semibold leading-none
          rounded-sm cursor-pointer select-none
          transition-colors duration-150
          ${isActive
            ? "bg-primary text-primary-foreground ring-2 ring-primary/30"
            : "bg-muted-foreground/15 text-muted-foreground hover:bg-muted-foreground/25 hover:text-foreground"
          }
        `}
      >
        {index}
      </sup>

      {open && (
        <div
          onMouseEnter={handleMouseEnter}
          onMouseLeave={handleMouseLeave}
          className="
            absolute bottom-full left-1/2 -translate-x-1/2 mb-2 z-50
            w-64 rounded-lg border bg-popover text-popover-foreground
            shadow-lg animate-in fade-in zoom-in-95
          "
        >
          <div className="px-3 py-2.5">
            <SourcePreview source={source} />
          </div>
          <div
            className="
              absolute top-full left-1/2 -translate-x-1/2
              w-2 h-2 -mt-[3px]
              bg-popover border-r border-b
              rotate-45
            "
          />
        </div>
      )}
    </span>
  );
}
