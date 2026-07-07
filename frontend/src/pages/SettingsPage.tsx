import { useState } from "react";
import { useTheme } from "@/hooks/useTheme";
import { Bug, Moon, Sun, Monitor } from "lucide-react";

interface SettingRowProps {
  label: string;
  description?: string;
  children: React.ReactNode;
}

function SettingRow({ label, description, children }: SettingRowProps) {
  return (
    <div className="flex items-start justify-between gap-6 py-4 border-b last:border-0">
      <div className="flex-1">
        <p className="text-sm font-medium">{label}</p>
        {description && (
          <p className="text-xs text-muted-foreground mt-0.5">{description}</p>
        )}
      </div>
      <div className="shrink-0">{children}</div>
    </div>
  );
}

interface ThemeButtonProps {
  value: "light" | "dark";
  current: string;
  icon: React.ReactNode;
  label: string;
  onClick: () => void;
}

function ThemeButton({ value, current, icon, label, onClick }: ThemeButtonProps) {
  const active = current === value;
  return (
    <button
      onClick={onClick}
      className={`flex items-center gap-1.5 px-3 py-1.5 rounded-md text-xs font-medium transition-colors ${
        active
          ? "bg-primary text-primary-foreground"
          : "bg-muted text-muted-foreground hover:bg-accent hover:text-accent-foreground"
      }`}
    >
      {icon}
      {label}
    </button>
  );
}

function ToggleSwitch({ checked, onChange }: { checked: boolean; onChange: (v: boolean) => void }) {
  return (
    <button
      role="switch"
      aria-checked={checked}
      onClick={() => onChange(!checked)}
      className={`relative inline-flex h-6 w-11 items-center rounded-full transition-colors ${
        checked ? "bg-primary" : "bg-muted-foreground/30"
      }`}
    >
      <span
        className={`inline-block h-4 w-4 rounded-full bg-white transition-transform ${
          checked ? "translate-x-6" : "translate-x-1"
        }`}
      />
    </button>
  );
}

const CONFIG_FIELDS = [
  {
    label: "Backend URL",
    description: "FastAPI server address",
    value: "http://localhost:8000",
  },
  {
    label: "LLM Model",
    description: "Ollama model used for generating answers",
    value: "llama3.2:1b",
  },
  {
    label: "Embedding Model",
    description: "SentenceTransformer model for vector embeddings",
    value: "multilingual-e5-small",
  },
  {
    label: "Vision Model",
    description: "Ollama model for image captioning (multimodal)",
    value: "llava:7b",
  },
  {
    label: "Default Top-K",
    description: "Number of document chunks retrieved per query",
    value: "5",
  },
  {
    label: "Chunk Size",
    description: "Character count per text chunk",
    value: "512",
  },
  {
    label: "Context Window",
    description: "LLM context window size in tokens",
    value: "8192",
  },
  {
    label: "Max Output Tokens",
    description: "Maximum tokens in LLM response",
    value: "4096",
  },
];

export function SettingsPage() {
  const { theme, toggleTheme } = useTheme();
  const [debugMode, setDebugMode] = useState(() => {
    try { return localStorage.getItem("mg-debug-mode") === "true"; } catch { return false; }
  });

  const handleDebugToggle = (v: boolean) => {
    setDebugMode(v);
    try { localStorage.setItem("mg-debug-mode", String(v)); } catch {}
  };

  return (
    <div className="max-w-2xl mx-auto space-y-8">
      {/* Header */}
      <div>
        <h1 className="text-3xl font-bold tracking-tight">Settings</h1>
        <p className="mt-1 text-sm text-muted-foreground">
          View system configuration and UI preferences
        </p>
      </div>

      {/* Appearance */}
      <section className="rounded-xl border bg-card p-6 space-y-1">
        <h2 className="text-base font-semibold mb-4">Appearance</h2>
        <SettingRow
          label="Theme"
          description="Controls the color scheme of the interface"
        >
          <div className="flex items-center gap-1.5">
            <ThemeButton
              value="light"
              current={theme}
              icon={<Sun className="h-3.5 w-3.5" />}
              label="Light"
              onClick={() => theme !== "light" && toggleTheme()}
            />
            <ThemeButton
              value="dark"
              current={theme}
              icon={<Moon className="h-3.5 w-3.5" />}
              label="Dark"
              onClick={() => theme !== "dark" && toggleTheme()}
            />
            <button
              className="flex items-center gap-1.5 px-3 py-1.5 rounded-md text-xs font-medium text-muted-foreground bg-muted hover:bg-accent transition-colors"
              onClick={() => {
                const prefersDark = window.matchMedia("(prefers-color-scheme: dark)").matches;
                if ((prefersDark && theme !== "dark") || (!prefersDark && theme !== "light")) {
                  toggleTheme();
                }
              }}
            >
              <Monitor className="h-3.5 w-3.5" />
              System
            </button>
          </div>
        </SettingRow>
      </section>

      {/* Developer */}
      <section className="rounded-xl border bg-card p-6 space-y-1">
        <h2 className="text-base font-semibold mb-4">Developer</h2>
        <SettingRow
          label="Debug Mode"
          description="Show detailed pipeline information, retrieved chunks, prompts, and timing data below each response in the chat"
        >
          <div className="flex items-center gap-2">
            <ToggleSwitch checked={debugMode} onChange={handleDebugToggle} />
            {debugMode && <Bug className="h-4 w-4 text-primary" />}
          </div>
        </SettingRow>
      </section>

      {/* System Configuration (read-only) */}
      <section className="rounded-xl border bg-card p-6 space-y-1">
        <h2 className="text-base font-semibold mb-1">System Configuration</h2>
        <p className="text-xs text-muted-foreground mb-4">
          These values are set via the backend <code className="bg-muted px-1 rounded text-[11px]">.env</code> file
          and cannot be changed from the UI.
        </p>
        {CONFIG_FIELDS.map(({ label, description, value }) => (
          <SettingRow key={label} label={label} description={description}>
            <code className="text-xs bg-muted px-2 py-1 rounded font-mono">{value}</code>
          </SettingRow>
        ))}
      </section>

      {/* About */}
      <section className="rounded-xl border bg-card p-6 space-y-3">
        <h2 className="text-base font-semibold">About MachineGuru</h2>
        <dl className="space-y-2 text-sm">
          {[
            ["Version", "0.2.0"],
            ["Frontend", "React 19 + Vite + TailwindCSS"],
            ["Backend", "FastAPI + Uvicorn"],
            ["Vector DB", "Qdrant"],
            ["LLM Runtime", "Ollama"],
            ["Retrieval", "Hybrid (Dense + BM25)"],
            ["Multimodal", "Image extraction + Vision captioning"],
            ["Architecture", "Clean Architecture (RAG)"],
          ].map(([k, v]) => (
            <div key={String(k)} className="flex justify-between border-b pb-2 last:border-0 last:pb-0">
              <dt className="text-muted-foreground">{k}</dt>
              <dd className="font-medium">{v}</dd>
            </div>
          ))}
        </dl>
      </section>
    </div>
  );
}
