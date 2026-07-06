import { useMemo, useState, useCallback } from "react";
import Markdown from "react-markdown";
import { ChevronDown, ChevronUp, FileText } from "lucide-react";
import type { SourceReference } from "@/types";
import { CitationBadge } from "./CitationBadge";

interface Props {
  content: string;
  sources: SourceReference[];
}

const CITATION_RE = /\[Source (\d+)\]/g;

export function CitationRenderer({ content, sources }: Props) {
  const [activeSource, setActiveSource] = useState<number | null>(null);
  const [sourcesOpen, setSourcesOpen] = useState(false);

  const handleBadgeClick = useCallback((idx: number) => {
    setActiveSource((prev) => (prev === idx ? null : idx));
    setSourcesOpen(true);
  }, []);

  const segments = useMemo(() => {
    const parts: { type: "text" | "citation"; content?: string; index?: number }[] = [];
    let lastIndex = 0;
    let match: RegExpExecArray | null;

    const regex = new RegExp(CITATION_RE.source, "g");
    while ((match = regex.exec(content)) !== null) {
      if (match.index > lastIndex) {
        parts.push({ type: "text", content: content.slice(lastIndex, match.index) });
      }
      const citationNum = match[1] ? parseInt(match[1]) : 1;
      parts.push({ type: "citation", index: citationNum });
      lastIndex = regex.lastIndex;
    }

    if (lastIndex < content.length) {
      parts.push({ type: "text", content: content.slice(lastIndex) });
    }

    return parts;
  }, [content]);

  const hasSources = sources.length > 0;

  return (
    <div className="space-y-3">
      <div className="leading-relaxed">
        {segments.map((seg, i) => {
          if (seg.type === "text") {
            return (
              <span key={i} className="inline-markdown">
                <Markdown
                  components={{
                    p: ({ children }) => <span>{children}</span>,
                  }}
                >
                  {seg.content ?? ""}
                </Markdown>
              </span>
            );
          }
          const idx = (seg.index ?? 1) - 1;
          const source = sources[idx];
          if (!source) {
            return <sup key={i} className="text-muted-foreground text-[10px]">[{seg.index}]</sup>;
          }
          return (
            <CitationBadge
              key={i}
              index={seg.index!}
              source={source}
              isActive={activeSource === idx}
              onClick={() => handleBadgeClick(idx)}
            />
          );
        })}
      </div>

      {hasSources && (
        <div className="border rounded-lg overflow-hidden">
          <button
            type="button"
            onClick={() => setSourcesOpen((v) => !v)}
            className="flex items-center justify-between w-full px-3 py-2 text-xs font-medium text-muted-foreground hover:text-foreground transition-colors bg-muted/30"
          >
            <span className="flex items-center gap-1.5">
              <FileText className="h-3 w-3" />
              {sources.length} source{sources.length > 1 ? "s" : ""}
            </span>
            {sourcesOpen ? (
              <ChevronUp className="h-3 w-3" />
            ) : (
              <ChevronDown className="h-3 w-3" />
            )}
          </button>

          {sourcesOpen && (
            <div className="divide-y">
              {sources.map((source, i) => (
                <div
                  key={i}
                  data-source-index={i}
                  className={`
                    flex items-start gap-2 px-3 py-2 text-xs transition-colors
                    ${activeSource === i ? "bg-primary/5 ring-1 ring-primary/20" : "hover:bg-muted/50"}
                  `}
                >
                  <span className={`
                    flex-shrink-0 w-4 h-4 flex items-center justify-center rounded text-[9px] font-semibold
                    ${activeSource === i
                      ? "bg-primary text-primary-foreground"
                      : "bg-muted-foreground/15 text-muted-foreground"
                    }
                  `}>
                    {i + 1}
                  </span>
                  <div className="min-w-0 flex-1 space-y-0.5">
                    <p className="font-medium truncate">{source.filename}</p>
                    <div className="flex flex-wrap gap-1.5 text-[10px] text-muted-foreground">
                      {source.page != null && source.page > 0 && (
                        <span>p.{source.page}</span>
                      )}
                      {source.chunk_index != null && (
                        <span>chunk #{source.chunk_index}</span>
                      )}
                      {source.score != null && (
                        <span>{(source.score * 100).toFixed(0)}% match</span>
                      )}
                    </div>
                  </div>
                </div>
              ))}
            </div>
          )}
        </div>
      )}
    </div>
  );
}
