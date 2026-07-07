import { useEffect, useRef, useState } from "react";
import {
  AlertCircle,
  Bug,
  Clock,
  Cpu,
  Download,
  Hash,
  Loader2,
  RefreshCw,
  Trash2,
  Zap,
} from "lucide-react";
import { useChat } from "@/hooks/useChat";
import { useDocuments } from "@/context/DocumentContext";
import { ChatInput } from "@/components/chat/ChatInput";
import { ChatMessage } from "@/components/chat/ChatMessage";
import { ActiveDocumentBar } from "@/components/chat/ActiveDocumentBar";
import { DebugPanel } from "@/components/chat/DebugPanel";
import { Button } from "@/components/ui/button";

export function ChatPage() {
  const { messages, isLoading, error, send, cancel, clear, regenerate, deleteMessage, exportMarkdown } = useChat();
  const { activeDocument, queryMode, refresh } = useDocuments();
  const bottomRef = useRef<HTMLDivElement>(null);
  const [debugMode, setDebugMode] = useState(() => {
    try { return localStorage.getItem("mg-debug-mode") === "true"; } catch { return false; }
  });

  // Auto-scroll to bottom when new messages come in
  useEffect(() => {
    bottomRef.current?.scrollIntoView({ behavior: "smooth" });
  }, [messages]);

  // Refresh documents on mount (catches new uploads)
  useEffect(() => {
    refresh();
  }, [refresh]);

  const toggleDebug = () => {
    const next = !debugMode;
    setDebugMode(next);
    try { localStorage.setItem("mg-debug-mode", String(next)); } catch {}
  };

  const isEmpty = messages.length === 0;

  const handleSend = (text: string) => {
    const docId = queryMode === "current" ? activeDocument?.document_id : undefined;
    send(text, true, docId ?? null);
  };

  const handleExportMd = () => {
    const md = exportMarkdown();
    const blob = new Blob([md], { type: "text/markdown" });
    const url = URL.createObjectURL(blob);
    const a = document.createElement("a");
    a.href = url;
    a.download = `machineguru-chat-${Date.now()}.md`;
    a.click();
    URL.revokeObjectURL(url);
  };

  return (
    <div className="flex flex-col h-full max-w-4xl mx-auto w-full">
      {/* Header */}
      <div className="flex items-center justify-between pb-4 border-b shrink-0">
        <div>
          <h1 className="text-2xl font-bold tracking-tight">Chat</h1>
          <p className="text-sm text-muted-foreground mt-0.5">
            Ask questions about your uploaded documents
          </p>
        </div>
        <div className="flex items-center gap-2">
          <Button
            variant={debugMode ? "default" : "ghost"}
            size="sm"
            onClick={toggleDebug}
            title="Toggle debug mode"
          >
            <Bug className="h-4 w-4" />
          </Button>

          {messages.length > 0 && (
            <>
              {isLoading && (
                <Button variant="outline" size="sm" onClick={cancel}>
                  <RefreshCw className="h-4 w-4 mr-1.5" />
                  Stop
                </Button>
              )}
              <Button variant="ghost" size="sm" onClick={handleExportMd} title="Export chat as Markdown">
                <Download className="h-4 w-4 mr-1.5" />
                Export
              </Button>
              <Button variant="ghost" size="sm" onClick={clear}>
                <Trash2 className="h-4 w-4 mr-1.5" />
                Clear
              </Button>
            </>
          )}
        </div>
      </div>

      {/* Active Document Bar */}
      <div className="shrink-0 pt-4">
        <ActiveDocumentBar />
      </div>

      {/* Messages area */}
      <div className="flex-1 overflow-y-auto py-6 space-y-6 min-h-0">
        {isEmpty && !isLoading && (
          <div className="flex flex-col items-center justify-center h-full text-center gap-4 text-muted-foreground py-20">
            <div className="rounded-full bg-muted p-5">
              <svg
                xmlns="http://www.w3.org/2000/svg"
                className="h-10 w-10 text-muted-foreground/60"
                fill="none"
                viewBox="0 0 24 24"
                stroke="currentColor"
              >
                <path
                  strokeLinecap="round"
                  strokeLinejoin="round"
                  strokeWidth={1.5}
                  d="M8 10h.01M12 10h.01M16 10h.01M9 16H5a2 2 0 01-2-2V6a2 2 0 012-2h14a2 2 0 012 2v8a2 2 0 01-2 2h-5l-5 5v-5z"
                />
              </svg>
            </div>
            <div>
              <p className="font-medium text-foreground">No messages yet</p>
              <p className="text-sm mt-1">
                {activeDocument
                  ? `Ask anything about "${activeDocument.filename}"`
                  : "Upload a document first, then start asking questions."}
              </p>
            </div>
            <div className="grid grid-cols-1 gap-2 text-sm w-full max-w-md mt-2">
              {[
                "What is this document about?",
                "Summarize the key findings",
                "What are the main components mentioned?",
                "Explain the wiring diagram",
                "What maintenance procedures are described?",
              ].map((suggestion) => (
                <button
                  key={suggestion}
                  onClick={() => handleSend(suggestion)}
                  className="rounded-lg border px-4 py-2.5 text-left text-muted-foreground hover:bg-accent hover:text-accent-foreground transition-colors"
                >
                  {suggestion}
                </button>
              ))}
            </div>
          </div>
        )}

        {messages.map((msg) => (
          <div key={msg.id} className="space-y-1">
            <ChatMessage
              message={msg}
              onRegenerate={regenerate}
              onDelete={deleteMessage}
            />

            {/* Response metadata (only for completed assistant messages) */}
            {msg.role === "assistant" && msg.content && msg.responseTimeMs != null && (
              <div className="flex items-center gap-3 text-[11px] text-muted-foreground/60 ml-11 flex-wrap">
                <span className="flex items-center gap-1">
                  <Clock className="h-3 w-3" />
                  {msg.responseTimeMs > 1000
                    ? `${(msg.responseTimeMs / 1000).toFixed(1)}s`
                    : `${msg.responseTimeMs}ms`}
                </span>
                {msg.timings?.first_token_ms != null && (
                  <span className="flex items-center gap-1">
                    <Zap className="h-3 w-3" />
                    First token: {msg.timings.first_token_ms > 1000
                      ? `${(msg.timings.first_token_ms / 1000).toFixed(1)}s`
                      : `${msg.timings.first_token_ms}ms`}
                  </span>
                )}
                {msg.retrievedChunks != null && (
                  <span className="flex items-center gap-1">
                    <Hash className="h-3 w-3" />
                    {msg.retrievedChunks} chunks
                  </span>
                )}
                {msg.citations && msg.citations.length > 0 && (
                  <span>{msg.citations.length} citations</span>
                )}
                {msg.timings && (
                  <span className="flex items-center gap-1">
                    <Cpu className="h-3 w-3" />
                    LLM: {msg.timings.llm_generation_ms > 1000
                      ? `${(msg.timings.llm_generation_ms / 1000).toFixed(1)}s`
                      : `${msg.timings.llm_generation_ms}ms`}
                  </span>
                )}
                {msg.model && (
                  <span className="text-muted-foreground/40">
                    {msg.model}
                  </span>
                )}
                {/* Source document pages */}
                {msg.sources && msg.sources.length > 0 && (
                  <span className="text-muted-foreground/40">
                    Pages: {[...new Set(msg.sources.map(s => s.page).filter(Boolean))].join(", ")}
                  </span>
                )}
                {/* Figure references */}
                {msg.sources?.some(s => s.chunk_type === "image") && (
                  <span className="text-muted-foreground/40">
                    📷 {msg.sources.filter(s => s.chunk_type === "image").length} figures
                  </span>
                )}
              </div>
            )}

            {/* Debug panel */}
            {debugMode && msg.role === "assistant" && msg.content && (
              <DebugPanel message={msg} />
            )}
          </div>
        ))}

        {/* Streaming indicator */}
        {isLoading && messages[messages.length - 1]?.role === "assistant" &&
          messages[messages.length - 1]?.content === "" && (
            <div className="flex gap-3">
              <div className="flex h-8 w-8 shrink-0 items-center justify-center rounded-full bg-muted">
                <Loader2 className="h-4 w-4 animate-spin text-muted-foreground" />
              </div>
              <div className="rounded-lg bg-muted px-4 py-3">
                <span className="flex gap-1 items-center h-5">
                  <span className="w-1.5 h-1.5 rounded-full bg-muted-foreground/50 animate-bounce [animation-delay:-0.3s]" />
                  <span className="w-1.5 h-1.5 rounded-full bg-muted-foreground/50 animate-bounce [animation-delay:-0.15s]" />
                  <span className="w-1.5 h-1.5 rounded-full bg-muted-foreground/50 animate-bounce" />
                </span>
              </div>
              <span className="self-center text-xs text-muted-foreground animate-pulse">
                Generating response…
              </span>
            </div>
          )}

        {/* Streaming in-progress indicator (when content has started arriving) */}
        {isLoading && messages[messages.length - 1]?.role === "assistant" &&
          messages[messages.length - 1]?.content !== "" && (
            <div className="flex items-center gap-2 ml-11 text-xs text-muted-foreground">
              <Loader2 className="h-3 w-3 animate-spin" />
              <span className="animate-pulse">Streaming…</span>
            </div>
          )}

        <div ref={bottomRef} />
      </div>

      {/* Error */}
      {error && (
        <div className="flex items-center gap-2 rounded-lg border border-red-200 bg-red-50 dark:border-red-900 dark:bg-red-950/30 px-4 py-3 text-sm text-red-600 dark:text-red-400 shrink-0 mb-2">
          <AlertCircle className="h-4 w-4 shrink-0" />
          {error}
        </div>
      )}

      {/* Input — pinned to bottom */}
      <div className="shrink-0 border-t pt-4">
        <ChatInput onSend={handleSend} disabled={isLoading} />
      </div>
    </div>
  );
}
