import { useEffect, useRef, useState } from "react";
import { Bot, Clock, FileText, Search, Trash2, User } from "lucide-react";
import type { ChatMessage } from "@/types";

interface Session {
  id: string;
  startedAt: string;
  messages: ChatMessage[];
  preview: string;
}

const HISTORY_KEY = "mg-chat-history";

function loadHistory(): Session[] {
  try {
    const raw = localStorage.getItem(HISTORY_KEY);
    return raw ? (JSON.parse(raw) as Session[]) : [];
  } catch {
    return [];
  }
}

export function HistoryPage() {
  const [sessions, setSessions] = useState<Session[]>(() => loadHistory());
  const [search, setSearch] = useState("");
  const [selected, setSelected] = useState<Session | null>(null);
  const searchRef = useRef<HTMLInputElement>(null);

  // Keep sessions up-to-date if another tab modifies localStorage
  useEffect(() => {
    const handler = () => setSessions(loadHistory());
    window.addEventListener("storage", handler);
    return () => window.removeEventListener("storage", handler);
  }, []);

  const filtered = sessions.filter(
    (s) =>
      s.preview.toLowerCase().includes(search.toLowerCase()) ||
      s.messages.some((m) =>
        m.content.toLowerCase().includes(search.toLowerCase()),
      ),
  );

  const deleteSession = (id: string) => {
    const updated = sessions.filter((s) => s.id !== id);
    setSessions(updated);
    localStorage.setItem(HISTORY_KEY, JSON.stringify(updated));
    if (selected?.id === id) setSelected(null);
  };

  return (
    <div className="max-w-5xl mx-auto space-y-6">
      {/* Header */}
      <div>
        <h1 className="text-3xl font-bold tracking-tight">History</h1>
        <p className="mt-1 text-sm text-muted-foreground">
          Browse past chat sessions stored in your browser
        </p>
      </div>

      {/* Search */}
      <div className="relative">
        <Search className="absolute left-3 top-1/2 -translate-y-1/2 h-4 w-4 text-muted-foreground pointer-events-none" />
        <input
          ref={searchRef}
          value={search}
          onChange={(e) => setSearch(e.target.value)}
          placeholder="Search conversations…"
          className="w-full pl-9 pr-4 py-2 rounded-lg border bg-card text-sm focus:outline-none focus:ring-2 focus:ring-ring"
        />
      </div>

      {sessions.length === 0 ? (
        <div className="flex flex-col items-center justify-center gap-3 rounded-xl border bg-muted/20 py-20 text-muted-foreground">
          <Clock className="h-10 w-10 opacity-40" />
          <div className="text-center">
            <p className="font-medium text-foreground">No history yet</p>
            <p className="text-sm mt-1">
              Your chat sessions will appear here once you start chatting.
            </p>
          </div>
        </div>
      ) : (
        <div className="grid gap-6 md:grid-cols-[280px_1fr]">
          {/* Session list */}
          <div className="space-y-2 overflow-y-auto max-h-[calc(100vh-220px)]">
            {filtered.length === 0 && (
              <p className="text-sm text-muted-foreground text-center py-6">
                No results for "{search}"
              </p>
            )}
            {filtered.map((session) => (
              <button
                key={session.id}
                onClick={() => setSelected(session)}
                className={`w-full text-left rounded-lg border p-3 text-sm transition-colors ${
                  selected?.id === session.id
                    ? "border-primary bg-primary/5"
                    : "bg-card hover:bg-accent"
                }`}
              >
                <div className="flex items-start justify-between gap-2">
                  <p className="font-medium line-clamp-2 flex-1">{session.preview}</p>
                  <button
                    onClick={(e) => {
                      e.stopPropagation();
                      deleteSession(session.id);
                    }}
                    className="shrink-0 text-muted-foreground hover:text-destructive transition-colors mt-0.5"
                    aria-label="Delete session"
                  >
                    <Trash2 className="h-3.5 w-3.5" />
                  </button>
                </div>
                <p className="text-xs text-muted-foreground mt-1.5 flex items-center gap-1">
                  <Clock className="h-3 w-3" />
                  {new Date(session.startedAt).toLocaleString()}
                  <span className="ml-1">·</span>
                  <span>{session.messages.length} messages</span>
                </p>
              </button>
            ))}
          </div>

          {/* Message detail */}
          <div className="rounded-xl border bg-card overflow-hidden">
            {!selected ? (
              <div className="flex flex-col items-center justify-center h-full gap-3 text-muted-foreground py-20">
                <FileText className="h-8 w-8 opacity-40" />
                <p className="text-sm">Select a session to view messages</p>
              </div>
            ) : (
              <div className="flex flex-col h-full max-h-[calc(100vh-220px)]">
                <div className="border-b px-5 py-3 flex items-center justify-between shrink-0">
                  <div>
                    <p className="font-medium text-sm">{selected.preview}</p>
                    <p className="text-xs text-muted-foreground mt-0.5">
                      {new Date(selected.startedAt).toLocaleString()} ·{" "}
                      {selected.messages.length} messages
                    </p>
                  </div>
                  <button
                    onClick={() => deleteSession(selected.id)}
                    className="text-muted-foreground hover:text-destructive transition-colors"
                    aria-label="Delete"
                  >
                    <Trash2 className="h-4 w-4" />
                  </button>
                </div>
                <div className="flex-1 overflow-y-auto p-5 space-y-4">
                  {selected.messages.map((msg) => (
                    <div
                      key={msg.id}
                      className={`flex gap-2 text-sm ${msg.role === "user" ? "flex-row-reverse" : ""}`}
                    >
                      <div className="flex h-7 w-7 shrink-0 items-center justify-center rounded-full bg-muted">
                        {msg.role === "user" ? (
                          <User className="h-3.5 w-3.5" />
                        ) : (
                          <Bot className="h-3.5 w-3.5" />
                        )}
                      </div>
                      <div
                        className={`rounded-lg px-3 py-2 max-w-[80%] ${
                          msg.role === "user"
                            ? "bg-primary text-primary-foreground"
                            : "bg-muted"
                        }`}
                      >
                        {msg.content || (
                          <span className="italic text-xs opacity-60">empty</span>
                        )}
                      </div>
                    </div>
                  ))}
                </div>
              </div>
            )}
          </div>
        </div>
      )}
    </div>
  );
}
