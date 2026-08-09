import { useCallback, useEffect, useRef, useState } from "react";

import { sendQuery, sendQueryStream } from "@/services/api";
import type { ChatMessage, SourceReference } from "@/types";

const HISTORY_KEY = "mg-chat-history";
const CURRENT_SESSION_KEY = "mg-current-session";

interface Session {
  id: string;
  startedAt: string;
  messages: ChatMessage[];
  preview: string;
}

// ── Persistence helpers ──────────────────────────────────────

function saveCurrentSession(messages: ChatMessage[]) {
  try {
    if (messages.length === 0) {
      localStorage.removeItem(CURRENT_SESSION_KEY);
      return;
    }
    localStorage.setItem(CURRENT_SESSION_KEY, JSON.stringify(messages));
  } catch {
    // Ignore localStorage errors
  }
}

function loadCurrentSession(): ChatMessage[] {
  try {
    const raw = localStorage.getItem(CURRENT_SESSION_KEY);
    if (!raw) return [];
    const messages = JSON.parse(raw) as ChatMessage[];
    // Filter out empty assistant messages (leftover from interrupted streams)
    return messages.filter(
      (m) => m.role === "user" || (m.role === "assistant" && m.content),
    );
  } catch {
    return [];
  }
}

function saveToHistory(messages: ChatMessage[]) {
  if (messages.length < 2) return;
  try {
    const raw = localStorage.getItem(HISTORY_KEY);
    const history: Session[] = raw ? JSON.parse(raw) : [];

    const firstUser = messages.find((m) => m.role === "user");
    const preview = firstUser?.content.slice(0, 120) ?? "Chat session";
    const sessionId = messages[0]?.id ?? crypto.randomUUID();

    const idx = history.findIndex((s) => s.id === sessionId);
    const session: Session = {
      id: sessionId,
      startedAt: messages[0]?.timestamp ?? new Date().toISOString(),
      messages,
      preview,
    };

    if (idx >= 0) {
      history[idx] = session;
    } else {
      history.unshift(session);
    }

    localStorage.setItem(HISTORY_KEY, JSON.stringify(history.slice(0, 50)));
  } catch {
    // Ignore localStorage errors
  }
}

// ── Hook ─────────────────────────────────────────────────────

export function useChat() {
  const [messages, setMessages] = useState<ChatMessage[]>(() =>
    loadCurrentSession(),
  );
  const [isLoading, setIsLoading] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const abortRef = useRef<AbortController | null>(null);
  const sessionIdRef = useRef<string | null>(null);

  // Initialize session ID from restored messages
  useEffect(() => {
    if (messages.length > 0 && !sessionIdRef.current) {
      sessionIdRef.current = messages[0]?.id ?? null;
    }
  }, []); // eslint-disable-line react-hooks/exhaustive-deps

  // Persist the current session whenever messages change
  // (debounced save — only when messages have content)
  useEffect(() => {
    // Only save non-empty sessions with at least a completed message pair
    const hasContent = messages.some(
      (m) => m.role === "assistant" && m.content,
    );
    if (messages.length > 0 && hasContent) {
      saveCurrentSession(messages);
      saveToHistory(messages);
    } else if (messages.length > 0) {
      // Still save to current session even if assistant hasn't responded yet
      saveCurrentSession(messages);
    }
  }, [messages]);

  const send = useCallback(
    async (text: string, useStream = true, documentId?: string | null) => {
      const user: ChatMessage = {
        id: crypto.randomUUID(),
        role: "user",
        content: text,
        timestamp: new Date().toISOString(),
      };

      if (!sessionIdRef.current) {
        sessionIdRef.current = user.id;
      }

      const assistantId = crypto.randomUUID();
      const sendTime = performance.now();
      const assistant: ChatMessage = {
        id: assistantId,
        role: "assistant",
        content: "",
        sources: [],
        timestamp: new Date().toISOString(),
      };

      setMessages((prev) => [...prev, user, assistant]);
      setIsLoading(true);
      setError(null);

      if (useStream) {
        const controller = new AbortController();
        abortRef.current = controller;

        let sources: SourceReference[] = [];

        await sendQueryStream(
          text,
          5,
          {
            onToken: (token) => {
              setMessages((prev) =>
                prev.map((m) =>
                  m.id === assistantId
                    ? { ...m, content: m.content + token }
                    : m,
                ),
              );
            },
            onSources: (raw) => {
              sources = raw as SourceReference[];
              setMessages((prev) =>
                prev.map((m) =>
                  m.id === assistantId
                    ? { ...m, sources, retrievedChunks: sources.length }
                    : m,
                ),
              );
            },
            onDone: (citations, timings, model) => {
              const responseTimeMs = Math.round(performance.now() - sendTime);
              setMessages((prev) =>
                prev.map((m) =>
                  m.id === assistantId
                    ? {
                        ...m,
                        citations: citations ?? undefined,
                        responseTimeMs,
                        retrievedChunks: sources.length,
                        timings: timings ?? undefined,
                        model: model ?? undefined,
                      }
                    : m,
                ),
              );
              setIsLoading(false);
            },
            onError: (err) => {
              // Remove the empty assistant message on error
              setMessages((prev) => {
                const updated = prev.map((m) =>
                  m.id === assistantId
                    ? { ...m, content: m.content || "[Error: " + err + "]" }
                    : m,
                );
                return updated;
              });
              setError(err);
              setIsLoading(false);
            },
          },
          controller.signal,
          documentId,
        );
      } else {
        try {
          const res = await sendQuery(text, 5, documentId);
          const responseTimeMs = Math.round(performance.now() - sendTime);
          setMessages((prev) =>
            prev.map((m) =>
              m.id === assistantId
                ? {
                    ...m,
                    content: res.answer,
                    sources: res.sources,
                    citations: res.citations ?? undefined,
                    responseTimeMs,
                    retrievedChunks: res.sources.length,
                    timings: res.timings ?? undefined,
                    model: res.model ?? undefined,
                  }
                : m,
            ),
          );
        } catch {
          setError("Failed to get response. Is the server running?");
        } finally {
          setIsLoading(false);
        }
      }
    },
    [],
  );

  const cancel = useCallback(() => {
    abortRef.current?.abort();
    setIsLoading(false);
  }, []);

  const clear = useCallback(() => {
    abortRef.current?.abort();
    setMessages((prev) => {
      if (prev.length > 1) saveToHistory(prev);
      return [];
    });
    setError(null);
    sessionIdRef.current = null;
    saveCurrentSession([]);
  }, []);

  const regenerate = useCallback(
    (messageId: string) => {
      setMessages((prev) => {
        // Find the assistant message to regenerate
        const msgIdx = prev.findIndex(
          (m) => m.id === messageId && m.role === "assistant",
        );
        if (msgIdx < 1) return prev;

        // Find the preceding user message
        const userMsg = prev[msgIdx - 1];
        if (userMsg?.role !== "user") return prev;

        // Remove the assistant message
        const next = prev.slice(0, msgIdx);

        // Re-send (will happen asynchronously)
        setTimeout(() => send(userMsg.content, true), 0);

        return next;
      });
    },
    [send],
  );

  const deleteMessage = useCallback((messageId: string) => {
    setMessages((prev) => {
      const idx = prev.findIndex((m) => m.id === messageId);
      if (idx < 0) return prev;

      // If it's a user message, also remove the following assistant message
      const msg = prev[idx]!;
      let next: ChatMessage[];
      if (
        msg.role === "user" &&
        idx + 1 < prev.length &&
        prev[idx + 1]!.role === "assistant"
      ) {
        next = [...prev.slice(0, idx), ...prev.slice(idx + 2)];
      } else if (
        msg.role === "assistant" &&
        idx > 0 &&
        prev[idx - 1]!.role === "user"
      ) {
        next = [...prev.slice(0, idx - 1), ...prev.slice(idx + 1)];
      } else {
        next = prev.filter((m) => m.id !== messageId);
      }

      return next;
    });
  }, []);

  const exportMarkdown = useCallback(() => {
    const lines = messages.map((m) => {
      const role = m.role === "user" ? "**You**" : "**MachineGuru**";
      const time = new Date(m.timestamp).toLocaleTimeString();
      return `### ${role} _(${time})_\n\n${m.content}\n`;
    });
    const md = `# MachineGuru Chat Export\n\n_Exported: ${new Date().toISOString()}_\n\n---\n\n${lines.join("\n---\n\n")}`;
    return md;
  }, [messages]);

  return {
    messages,
    isLoading,
    error,
    send,
    cancel,
    clear,
    regenerate,
    deleteMessage,
    exportMarkdown,
  };
}
