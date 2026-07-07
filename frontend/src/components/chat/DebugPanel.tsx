import { useState } from "react";
import { Bug, ChevronDown, ChevronRight } from "lucide-react";
import type { ChatMessage } from "@/types";

interface Props {
  message: ChatMessage;
}

export function DebugPanel({ message }: Props) {
  const [isOpen, setIsOpen] = useState(false);
  const { timings, debug, sources, model } = message;

  if (!timings && !debug) return null;

  return (
    <div className="ml-11 mt-2">
      <button
        onClick={() => setIsOpen(!isOpen)}
        className="flex items-center gap-1.5 text-[11px] text-muted-foreground/60 hover:text-muted-foreground transition-colors"
      >
        <Bug className="h-3 w-3" />
        {isOpen ? <ChevronDown className="h-3 w-3" /> : <ChevronRight className="h-3 w-3" />}
        <span>Debug Info</span>
      </button>

      {isOpen && (
        <div className="mt-2 rounded-lg border bg-muted/30 p-4 space-y-4 text-xs font-mono">
          {/* Timings */}
          {timings && (
            <div>
              <h4 className="font-semibold text-foreground mb-2 font-sans">⏱ Pipeline Timings</h4>
              <div className="grid grid-cols-2 gap-x-6 gap-y-1">
                <span className="text-muted-foreground">Embedding:</span>
                <span>{timings.embedding_ms}ms</span>
                <span className="text-muted-foreground">Qdrant Search:</span>
                <span>{timings.qdrant_search_ms}ms</span>
                {timings.prompt_build_ms != null && (
                  <>
                    <span className="text-muted-foreground">Prompt Build:</span>
                    <span>{timings.prompt_build_ms}ms</span>
                  </>
                )}
                {timings.first_token_ms != null && (
                  <>
                    <span className="text-muted-foreground">First Token:</span>
                    <span className={timings.first_token_ms > 2000 ? "text-red-500" : "text-green-500"}>
                      {timings.first_token_ms}ms
                    </span>
                  </>
                )}
                <span className="text-muted-foreground">LLM Generation:</span>
                <span>{timings.llm_generation_ms}ms</span>
                <span className="text-muted-foreground font-semibold">Total:</span>
                <span className="font-semibold">{timings.total_ms}ms</span>
              </div>
            </div>
          )}

          {/* Token Counts */}
          {timings && (timings.prompt_token_count || timings.context_token_count) && (
            <div>
              <h4 className="font-semibold text-foreground mb-2 font-sans">📊 Token Estimates</h4>
              <div className="grid grid-cols-2 gap-x-6 gap-y-1">
                {timings.prompt_token_count != null && (
                  <>
                    <span className="text-muted-foreground">Prompt Tokens:</span>
                    <span>~{timings.prompt_token_count}</span>
                  </>
                )}
                {timings.context_token_count != null && (
                  <>
                    <span className="text-muted-foreground">Context Tokens:</span>
                    <span>~{timings.context_token_count}</span>
                  </>
                )}
                <span className="text-muted-foreground">Context Chars:</span>
                <span>{timings.context_chars ?? "?"}</span>
              </div>
            </div>
          )}

          {/* Model & Retrieval */}
          <div>
            <h4 className="font-semibold text-foreground mb-2 font-sans">🤖 Model & Retrieval</h4>
            <div className="grid grid-cols-2 gap-x-6 gap-y-1">
              <span className="text-muted-foreground">Model:</span>
              <span>{model || "unknown"}</span>
              <span className="text-muted-foreground">Chunks Retrieved:</span>
              <span>{timings?.chunks_retrieved ?? sources?.length ?? "?"}</span>
              {timings?.retrieval_method && (
                <>
                  <span className="text-muted-foreground">Retrieval Method:</span>
                  <span>{timings.retrieval_method}</span>
                </>
              )}
            </div>
          </div>

          {/* Retrieved Chunks */}
          {debug?.retrieved_chunks && debug.retrieved_chunks.length > 0 && (
            <div>
              <h4 className="font-semibold text-foreground mb-2 font-sans">📄 Retrieved Chunks</h4>
              <div className="space-y-2 max-h-60 overflow-y-auto">
                {debug.retrieved_chunks.map((chunk) => (
                  <div key={chunk.source_index} className="rounded border p-2 bg-background/50">
                    <div className="flex items-center gap-2 text-muted-foreground mb-1">
                      <span className="font-semibold">[Source {chunk.source_index}]</span>
                      <span>score={chunk.score.toFixed(4)}</span>
                      <span>page={chunk.page ?? "?"}</span>
                      <span>type={chunk.chunk_type}</span>
                    </div>
                    <p className="text-foreground/80 line-clamp-3">{chunk.text_preview}</p>
                  </div>
                ))}
              </div>
            </div>
          )}

          {/* Prompts */}
          {debug?.system_prompt && (
            <div>
              <h4 className="font-semibold text-foreground mb-2 font-sans">📝 System Prompt</h4>
              <pre className="whitespace-pre-wrap text-foreground/70 max-h-32 overflow-y-auto bg-background/50 rounded p-2">
                {debug.system_prompt}
              </pre>
            </div>
          )}
          {debug?.user_prompt && (
            <div>
              <h4 className="font-semibold text-foreground mb-2 font-sans">💬 User Prompt</h4>
              <pre className="whitespace-pre-wrap text-foreground/70 max-h-40 overflow-y-auto bg-background/50 rounded p-2">
                {debug.user_prompt}
              </pre>
            </div>
          )}
        </div>
      )}
    </div>
  );
}
