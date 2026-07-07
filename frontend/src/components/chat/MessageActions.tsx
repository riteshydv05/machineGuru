import { useState } from "react";
import { Check, ClipboardCopy, Download, RefreshCw, Trash2 } from "lucide-react";

interface Props {
  content: string;
  messageId: string;
  onRegenerate?: (id: string) => void;
  onDelete?: (id: string) => void;
}

export function MessageActions({ content, messageId, onRegenerate, onDelete }: Props) {
  const [copied, setCopied] = useState(false);

  const handleCopy = async () => {
    try {
      await navigator.clipboard.writeText(content);
      setCopied(true);
      setTimeout(() => setCopied(false), 2000);
    } catch {
      // Fallback
      const ta = document.createElement("textarea");
      ta.value = content;
      document.body.appendChild(ta);
      ta.select();
      document.execCommand("copy");
      document.body.removeChild(ta);
      setCopied(true);
      setTimeout(() => setCopied(false), 2000);
    }
  };

  const handleExportMd = () => {
    const blob = new Blob([content], { type: "text/markdown" });
    const url = URL.createObjectURL(blob);
    const a = document.createElement("a");
    a.href = url;
    a.download = `machineguru-response-${Date.now()}.md`;
    a.click();
    URL.revokeObjectURL(url);
  };

  return (
    <div className="flex items-center gap-1 opacity-0 group-hover:opacity-100 transition-opacity">
      <button
        onClick={handleCopy}
        className="p-1.5 rounded-md text-muted-foreground hover:bg-accent hover:text-accent-foreground transition-colors"
        title={copied ? "Copied!" : "Copy to clipboard"}
      >
        {copied ? <Check className="h-3.5 w-3.5 text-green-500" /> : <ClipboardCopy className="h-3.5 w-3.5" />}
      </button>

      <button
        onClick={handleExportMd}
        className="p-1.5 rounded-md text-muted-foreground hover:bg-accent hover:text-accent-foreground transition-colors"
        title="Export as Markdown"
      >
        <Download className="h-3.5 w-3.5" />
      </button>

      {onRegenerate && (
        <button
          onClick={() => onRegenerate(messageId)}
          className="p-1.5 rounded-md text-muted-foreground hover:bg-accent hover:text-accent-foreground transition-colors"
          title="Regenerate response"
        >
          <RefreshCw className="h-3.5 w-3.5" />
        </button>
      )}

      {onDelete && (
        <button
          onClick={() => onDelete(messageId)}
          className="p-1.5 rounded-md text-muted-foreground hover:bg-red-100 hover:text-red-600 dark:hover:bg-red-950/30 dark:hover:text-red-400 transition-colors"
          title="Delete message"
        >
          <Trash2 className="h-3.5 w-3.5" />
        </button>
      )}
    </div>
  );
}
