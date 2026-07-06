import { useEffect, useState } from "react";
import { Activity, AlertCircle, CheckCircle2, Database, FileText, Loader2, Cpu, RefreshCw } from "lucide-react";
import { healthCheck } from "@/services/api";
import type { HealthResponse } from "@/types";

interface StatCard {
  label: string;
  value: string | number;
  icon: React.ReactNode;
  status?: "ok" | "warn" | "error";
}

function StatusDot({ status }: { status?: "ok" | "warn" | "error" }) {
  const colors = {
    ok: "bg-green-500",
    warn: "bg-yellow-400",
    error: "bg-red-500",
  };
  return (
    <span
      className={`inline-block h-2 w-2 rounded-full ${status ? colors[status] : "bg-gray-400"} shrink-0`}
    />
  );
}

export function DashboardPage() {
  const [health, setHealth] = useState<HealthResponse | null>(null);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);
  const [lastRefresh, setLastRefresh] = useState<Date>(new Date());

  useEffect(() => {
    let mounted = true;

    const fetchHealth = async () => {
      try {
        const data = await healthCheck();
        if (mounted) {
          setHealth(data);
          setError(null); // ← clear any previous error on recovery
          setLoading(false);
          setLastRefresh(new Date());
        }
      } catch {
        if (mounted) {
          setError(
            "Backend is not reachable. Make sure the server is running on port 8001 (or check your Vite proxy config).",
          );
          setLoading(false);
        }
      }
    };

    fetchHealth();
    const id = setInterval(fetchHealth, 15_000);
    return () => {
      mounted = false;
      clearInterval(id);
    };
  }, []);

  // health.status is "healthy" | "degraded" | "unhealthy"
  const qdrantStatus = health?.qdrant?.connected ? "ok" : health ? "error" : undefined;
  const backendStatus = health
    ? health.status === "healthy"
      ? "ok"
      : "warn"
    : error
      ? "error"
      : undefined;

  const cards: StatCard[] = [
    {
      label: "Backend",
      value: health?.status ?? (error ? "Offline" : "—"),
      icon: <Activity className="h-5 w-5 text-blue-500" />,
      status: backendStatus,
    },
    {
      label: "Qdrant",
      value: health?.qdrant?.connected ? "Connected" : "Disconnected",
      icon: <Database className="h-5 w-5 text-purple-500" />,
      status: qdrantStatus,
    },
    {
      label: "Documents",
      value: health?.qdrant?.point_count ?? "—",
      icon: <FileText className="h-5 w-5 text-green-500" />,
      status: health ? "ok" : undefined,
    },
    {
      label: "Vector Size",
      value: health?.qdrant?.vector_size ?? "—",
      icon: <Cpu className="h-5 w-5 text-orange-500" />,
      status: health ? "ok" : undefined,
    },
  ];

  return (
    <div className="space-y-8 max-w-5xl mx-auto">
      {/* Header */}
      <div className="flex items-start justify-between">
        <div>
          <h1 className="text-3xl font-bold tracking-tight">Dashboard</h1>
          <p className="mt-1 text-muted-foreground text-sm">
            Real-time system health and document statistics
          </p>
        </div>
        {!loading && (
          <p className="text-xs text-muted-foreground mt-1">
            Last refresh: {lastRefresh.toLocaleTimeString()}
          </p>
        )}
      </div>

      {/* Loading */}
      {loading && (
        <div className="flex items-center gap-3 text-muted-foreground">
          <Loader2 className="h-5 w-5 animate-spin" />
          <span className="text-sm">Checking services…</span>
        </div>
      )}

      {/* Error banner — only show when no health data AND there's an error */}
      {error && !health && !loading && (
        <div className="flex items-start gap-3 rounded-lg border border-red-200 bg-red-50 dark:border-red-900 dark:bg-red-950/30 p-4">
          <AlertCircle className="h-5 w-5 text-red-500 mt-0.5 shrink-0" />
          <div className="flex-1">
            <p className="font-medium text-red-700 dark:text-red-400">Connection Failed</p>
            <p className="text-sm text-red-600 dark:text-red-500 mt-0.5">{error}</p>
          </div>
        </div>
      )}

      {/* Stat Cards */}
      {!loading && (
        <div className="grid gap-4 sm:grid-cols-2 lg:grid-cols-4">
          {cards.map((card) => (
            <div
              key={card.label}
              className="rounded-xl border bg-card p-5 space-y-3 shadow-sm hover:shadow-md transition-shadow"
            >
              <div className="flex items-center justify-between">
                <span className="text-xs font-medium uppercase tracking-wider text-muted-foreground">
                  {card.label}
                </span>
                {card.icon}
              </div>
              <div className="flex items-center gap-2">
                <StatusDot status={card.status} />
                <span className="text-lg font-semibold capitalize">{card.value}</span>
              </div>
            </div>
          ))}
        </div>
      )}

      {/* Service Details */}
      {health && !loading && (
        <div className="grid gap-6 md:grid-cols-2">
          {/* Backend Info */}
          <div className="rounded-xl border bg-card p-6 space-y-4">
            <div className="flex items-center gap-2">
              <CheckCircle2 className="h-5 w-5 text-green-500" />
              <h2 className="font-semibold">Backend</h2>
            </div>
            <dl className="space-y-2 text-sm">
              {[
                ["Status", health.status],
                ["Version", health.version],
                ["Uptime", health.uptime_seconds != null ? `${Math.floor(health.uptime_seconds)}s` : "—"],
                ["Timestamp", new Date(health.timestamp).toLocaleTimeString()],
              ].map(([k, v]) => (
                <div key={k} className="flex justify-between">
                  <dt className="text-muted-foreground">{k}</dt>
                  <dd className="font-medium capitalize">{v}</dd>
                </div>
              ))}
            </dl>
          </div>

          {/* Qdrant Info */}
          <div className="rounded-xl border bg-card p-6 space-y-4">
            <div className="flex items-center gap-2">
              <Database className="h-5 w-5 text-purple-500" />
              <h2 className="font-semibold">Qdrant Vector DB</h2>
            </div>
            {health.qdrant ? (
              <dl className="space-y-2 text-sm">
                {[
                  ["Connected", health.qdrant.connected ? "Yes" : "No"],
                  ["Collection", health.qdrant.collection ?? "—"],
                  ["Vectors stored", health.qdrant.point_count ?? "—"],
                  ["Vector dimensions", health.qdrant.vector_size ?? "—"],
                ].map(([k, v]) => (
                  <div key={k} className="flex justify-between">
                    <dt className="text-muted-foreground">{k}</dt>
                    <dd className="font-medium">{String(v)}</dd>
                  </div>
                ))}
              </dl>
            ) : (
              <p className="text-sm text-muted-foreground">Qdrant info unavailable</p>
            )}
          </div>
        </div>
      )}

      {/* Offline placeholder cards */}
      {error && !health && !loading && (
        <div className="grid gap-6 md:grid-cols-2 opacity-50">
          {["Backend", "Qdrant Vector DB"].map((title) => (
            <div key={title} className="rounded-xl border bg-card p-6 space-y-3">
              <div className="flex items-center gap-2">
                <RefreshCw className="h-5 w-5 text-muted-foreground" />
                <h2 className="font-semibold">{title}</h2>
              </div>
              <p className="text-sm text-muted-foreground">Waiting for connection…</p>
            </div>
          ))}
        </div>
      )}

      {/* Quick Start Guide */}
      <div className="rounded-xl border bg-card p-6 space-y-3">
        <h2 className="font-semibold">Quick Start</h2>
        <ol className="space-y-2 text-sm text-muted-foreground list-decimal list-inside">
          <li>Go to <strong className="text-foreground">Upload</strong> and drop in a PDF, TXT, or DOCX file</li>
          <li>Wait for the document to be processed and embedded</li>
          <li>Go to <strong className="text-foreground">Chat</strong> and ask questions about your document</li>
          <li>Hover over <strong className="text-foreground">[Source N]</strong> badges to preview citations</li>
        </ol>
      </div>
    </div>
  );
}
