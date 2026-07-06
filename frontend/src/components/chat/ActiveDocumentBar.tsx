import { ChevronDown, FileText, Layers, CheckCircle2, Globe, File } from "lucide-react";
import { useState, useRef, useEffect } from "react";
import { useDocuments } from "@/context/DocumentContext";
import { cn } from "@/utils/cn";

export function ActiveDocumentBar() {
  const {
    documents,
    activeDocument,
    queryMode,
    totalDocuments,
    setQueryMode,
    setActiveDocument,
  } = useDocuments();

  const [dropdownOpen, setDropdownOpen] = useState(false);
  const dropdownRef = useRef<HTMLDivElement>(null);

  // Close dropdown on outside click
  useEffect(() => {
    const handler = (e: MouseEvent) => {
      if (dropdownRef.current && !dropdownRef.current.contains(e.target as Node)) {
        setDropdownOpen(false);
      }
    };
    document.addEventListener("mousedown", handler);
    return () => document.removeEventListener("mousedown", handler);
  }, []);

  if (totalDocuments === 0) {
    return (
      <div className="rounded-lg border border-dashed bg-muted/30 p-3 flex items-center gap-3 text-sm text-muted-foreground">
        <FileText className="h-4 w-4 shrink-0" />
        <span>No documents uploaded yet. Upload a document to start chatting.</span>
      </div>
    );
  }

  const formatSize = (bytes: number) => {
    if (bytes < 1024) return `${bytes} B`;
    if (bytes < 1024 * 1024) return `${(bytes / 1024).toFixed(1)} KB`;
    return `${(bytes / (1024 * 1024)).toFixed(1)} MB`;
  };

  return (
    <div className="rounded-lg border bg-card p-3 space-y-2">
      {/* Top row: Active document + mode toggle */}
      <div className="flex items-center justify-between gap-3 flex-wrap">
        {/* Active document info */}
        <div className="flex items-center gap-3 min-w-0 flex-1">
          <div className="flex h-9 w-9 shrink-0 items-center justify-center rounded-lg bg-primary/10">
            <FileText className="h-4 w-4 text-primary" />
          </div>
          <div className="min-w-0">
            <p className="text-xs font-medium text-muted-foreground uppercase tracking-wider">
              Currently Chatting With
            </p>
            <p className="text-sm font-semibold truncate">
              {activeDocument?.filename ?? "No document selected"}
            </p>
          </div>
        </div>

        {/* Query mode toggle */}
        <div className="flex items-center gap-1.5 rounded-lg border bg-muted/50 p-0.5">
          <button
            onClick={() => setQueryMode("current")}
            className={cn(
              "flex items-center gap-1.5 rounded-md px-2.5 py-1 text-xs font-medium transition-colors",
              queryMode === "current"
                ? "bg-card text-foreground shadow-sm"
                : "text-muted-foreground hover:text-foreground",
            )}
          >
            <File className="h-3 w-3" />
            Current
          </button>
          <button
            onClick={() => setQueryMode("all")}
            className={cn(
              "flex items-center gap-1.5 rounded-md px-2.5 py-1 text-xs font-medium transition-colors",
              queryMode === "all"
                ? "bg-card text-foreground shadow-sm"
                : "text-muted-foreground hover:text-foreground",
            )}
          >
            <Globe className="h-3 w-3" />
            All Docs
          </button>
        </div>
      </div>

      {/* Stats row */}
      {activeDocument && (
        <div className="flex items-center gap-4 text-xs text-muted-foreground flex-wrap">
          <span className="flex items-center gap-1">
            <Layers className="h-3 w-3" />
            {activeDocument.page_count} Pages
          </span>
          <span>{activeDocument.chunk_count} Chunks</span>
          <span>{formatSize(activeDocument.size_bytes)}</span>
          <span className="flex items-center gap-1 text-green-600 dark:text-green-400">
            <CheckCircle2 className="h-3 w-3" />
            {activeDocument.status === "indexed" ? "Indexed" : activeDocument.status}
          </span>
          {totalDocuments > 1 && (
            <span className="text-muted-foreground/60">
              {totalDocuments} total documents
            </span>
          )}
        </div>
      )}

      {/* Document selector dropdown (only if multiple documents) */}
      {totalDocuments > 1 && (
        <div className="relative" ref={dropdownRef}>
          <button
            onClick={() => setDropdownOpen(!dropdownOpen)}
            className="flex items-center gap-1.5 text-xs text-muted-foreground hover:text-foreground transition-colors"
          >
            <ChevronDown className={cn("h-3 w-3 transition-transform", dropdownOpen && "rotate-180")} />
            Change document
          </button>

          {dropdownOpen && (
            <div className="absolute left-0 top-full mt-1 z-50 w-72 rounded-lg border bg-card shadow-lg py-1 max-h-48 overflow-y-auto">
              {documents.map((doc) => (
                <button
                  key={doc.document_id}
                  onClick={() => {
                    setActiveDocument(doc.document_id);
                    setDropdownOpen(false);
                  }}
                  className={cn(
                    "w-full text-left px-3 py-2 text-sm hover:bg-accent transition-colors flex items-center justify-between gap-2",
                    doc.document_id === activeDocument?.document_id && "bg-primary/5",
                  )}
                >
                  <div className="min-w-0">
                    <p className="truncate font-medium">{doc.filename}</p>
                    <p className="text-xs text-muted-foreground">
                      {doc.page_count} pages · {doc.chunk_count} chunks
                    </p>
                  </div>
                  {doc.document_id === activeDocument?.document_id && (
                    <CheckCircle2 className="h-3.5 w-3.5 text-primary shrink-0" />
                  )}
                </button>
              ))}
            </div>
          )}
        </div>
      )}
    </div>
  );
}
