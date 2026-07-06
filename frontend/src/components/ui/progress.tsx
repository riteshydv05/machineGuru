import { forwardRef } from "react";
import { cn } from "@/utils/cn";

interface ProgressProps {
  value: number;
  className?: string;
}

export const Progress = forwardRef<HTMLDivElement, ProgressProps>(
  ({ value, className }, ref) => (
    <div
      ref={ref}
      className={cn(
        "relative h-2 w-full overflow-hidden rounded-full bg-secondary",
        className,
      )}
    >
      <div
        className="h-full w-full flex-1 bg-primary transition-all duration-300"
        style={{ transform: `translateX(-${100 - Math.min(value, 100)}%)` }}
      />
    </div>
  ),
);
Progress.displayName = "Progress";
