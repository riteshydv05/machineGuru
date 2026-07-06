import { FileText } from "lucide-react";
import type { SourceReference } from "@/types";
import { Badge } from "@/components/ui/badge";

interface Props {
  source: SourceReference;
}

export function SourcePreview({ source }: Props) {
  return (
    <div className="space-y-2 p-1">
      <div className="flex items-center gap-2 font-medium text-sm">
        <FileText className="h-3.5 w-3.5 text-muted-foreground" />
        <span className="truncate max-w-[200px]">{source.filename}</span>
      </div>

      <div className="flex flex-wrap gap-1.5">
        {source.page != null && source.page > 0 && (
          <Badge variant="secondary" className="text-[10px] px-1.5 py-0">
            p.{source.page}
          </Badge>
        )}
        {source.chunk_index != null && (
          <Badge variant="secondary" className="text-[10px] px-1.5 py-0">
            chunk #{source.chunk_index}
          </Badge>
        )}
        {source.score != null && (
          <Badge variant="outline" className="text-[10px] px-1.5 py-0">
            {(source.score * 100).toFixed(0)}% match
          </Badge>
        )}
      </div>
    </div>
  );
}
