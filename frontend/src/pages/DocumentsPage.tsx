import { useCallback, useEffect, useState } from "react";
import {
  AlertCircle,
  ArrowUpDown,
  CheckCircle2,
  FileText,
  Image,
  Loader2,
  Search,
  Trash2,
  X,
} from "lucide-react";
import { useDocuments } from "@/context/DocumentContext";
import { Button } from "@/components/ui/button";

function formatBytes(bytes: number): string {
  if (bytes === 0) return "0 B";
  const k = 1024;
  const sizes = ["B", "KB", "MB", "GB"];
  const i = Math.floor(Math.log(bytes) / Math.log(k));
  return `${parseFloat((bytes / Math.pow(k, i)).toFixed(1))} ${sizes[i]}`;
}

function formatDate(isoDate: string): string {
  try {
    return new Date(isoDate).toLocaleDateString(undefined, {
      year: "numeric",
      month: "short",
      day: "numeric",
      hour: "2-digit",
      minute: "2-digit",
    });
  } catch {
    return isoDate;
  }
}

type SortField = "filename" | "uploaded_at" | "page_count" | "chunk_count" | "size_bytes";
type SortDir = "asc" | "desc";

export function DocumentsPage() {
  const { documents, activeDocument, loading, refresh, setActiveDocument, deleteDocument } = useDocuments();
  const [search, setSearch] = useState("");
  const [sortField, setSortField] = useState<SortField>("uploaded_at");
  const [sortDir, setSortDir] = useState<SortDir>("desc");
  const [deletingId, setDeletingId] = useState<string | null>(null);
  const [confirmDeleteId, setConfirmDeleteId] = useState<string | null>(null);
  const [notification, setNotification] = useState<{ type: "success" | "error"; message: string } | null>(null);

  useEffect(() => {
    refresh();
  }, [refresh]);

  // Auto-dismiss notifications
  useEffect(() => {
    if (notification) {
      const t = setTimeout(() => setNotification(null), 4000);
      return () => clearTimeout(t);
    }
  }, [notification]);

  const handleSort = (field: SortField) => {
    if (sortField === field) {
      setSortDir(sortDir === "asc" ? "desc" : "asc");
    } else {
      setSortField(field);
      setSortDir("desc");
    }
  };

  const handleDelete = useCallback(async (docId: string, filename: string) => {
    setDeletingId(docId);
    setConfirmDeleteId(null);
    try {
      await deleteDocument(docId);
      setNotification({ type: "success", message: `"${filename}" deleted successfully` });
    } catch {
      setNotification({ type: "error", message: `Failed to delete "${filename}"` });
    } finally {
      setDeletingId(null);
    }
  }, [deleteDocument]);

  // Filter and sort
  const filtered = documents
    .filter((d) => d.filename.toLowerCase().includes(search.toLowerCase()))
    .sort((a, b) => {
      const aVal = a[sortField];
      const bVal = b[sortField];
      const cmp = typeof aVal === "string" ? aVal.localeCompare(bVal as string) : (aVal as number) - (bVal as number);
      return sortDir === "asc" ? cmp : -cmp;
    });

  // Stats
  const totalStorage = documents.reduce((sum, d) => sum + d.size_bytes, 0);
  const totalPages = documents.reduce((sum, d) => sum + d.page_count, 0);
  const totalChunks = documents.reduce((sum, d) => sum + d.chunk_count, 0);
  const totalImages = documents.reduce((sum, d) => sum + (d.image_count ?? 0), 0);

  return (
    <div className="space-y-6 max-w-6xl mx-auto">
      {/* Header */}
      <div>
        <h1 className="text-2xl font-bold tracking-tight">Documents</h1>
        <p className="text-sm text-muted-foreground mt-0.5">
          Manage your uploaded documents and their embeddings
        </p>
      </div>

      {/* Notification */}
      {notification && (
        <div
          className={`flex items-center gap-2 rounded-lg border px-4 py-3 text-sm ${
            notification.type === "success"
              ? "border-green-200 bg-green-50 text-green-700 dark:border-green-900 dark:bg-green-950/30 dark:text-green-400"
              : "border-red-200 bg-red-50 text-red-700 dark:border-red-900 dark:bg-red-950/30 dark:text-red-400"
          }`}
        >
          {notification.type === "success" ? (
            <CheckCircle2 className="h-4 w-4 shrink-0" />
          ) : (
            <AlertCircle className="h-4 w-4 shrink-0" />
          )}
          {notification.message}
          <button onClick={() => setNotification(null)} className="ml-auto">
            <X className="h-4 w-4" />
          </button>
        </div>
      )}

      {/* Summary stats */}
      <div className="grid grid-cols-2 sm:grid-cols-5 gap-4">
        {[
          { label: "Documents", value: documents.length, icon: <FileText className="h-4 w-4 text-blue-500" /> },
          { label: "Total Pages", value: totalPages, icon: <FileText className="h-4 w-4 text-green-500" /> },
          { label: "Total Chunks", value: totalChunks.toLocaleString(), icon: <FileText className="h-4 w-4 text-purple-500" /> },
          { label: "Images", value: totalImages, icon: <Image className="h-4 w-4 text-teal-500" /> },
          { label: "Storage Used", value: formatBytes(totalStorage), icon: <FileText className="h-4 w-4 text-orange-500" /> },
        ].map((stat) => (
          <div key={stat.label} className="rounded-xl border bg-card p-4 space-y-1">
            <div className="flex items-center gap-2">
              {stat.icon}
              <span className="text-xs text-muted-foreground uppercase tracking-wider">{stat.label}</span>
            </div>
            <p className="text-lg font-semibold">{stat.value}</p>
          </div>
        ))}
      </div>

      {/* Search */}
      <div className="relative">
        <Search className="absolute left-3 top-1/2 -translate-y-1/2 h-4 w-4 text-muted-foreground" />
        <input
          type="text"
          placeholder="Search documents..."
          value={search}
          onChange={(e) => setSearch(e.target.value)}
          className="w-full pl-10 pr-4 py-2.5 rounded-lg border bg-background text-sm focus:outline-none focus:ring-2 focus:ring-primary/20"
        />
      </div>

      {/* Table */}
      {loading ? (
        <div className="flex items-center gap-2 text-muted-foreground justify-center py-12">
          <Loader2 className="h-5 w-5 animate-spin" />
          Loading documents…
        </div>
      ) : filtered.length === 0 ? (
        <div className="text-center py-12 text-muted-foreground">
          <FileText className="h-10 w-10 mx-auto mb-3 opacity-30" />
          <p>{search ? "No documents match your search" : "No documents uploaded yet"}</p>
        </div>
      ) : (
        <div className="rounded-xl border overflow-hidden">
          <div className="overflow-x-auto">
            <table className="w-full text-sm">
              <thead>
                <tr className="border-b bg-muted/50">
                  {([
                    ["filename", "Filename"],
                    ["uploaded_at", "Uploaded"],
                    ["page_count", "Pages"],
                    ["chunk_count", "Chunks"],
                    ["size_bytes", "Size"],
                  ] as [SortField, string][]).map(([field, label]) => (
                    <th
                      key={field}
                      className="text-left px-4 py-3 font-medium text-muted-foreground cursor-pointer hover:text-foreground transition-colors"
                      onClick={() => handleSort(field)}
                    >
                      <span className="flex items-center gap-1">
                        {label}
                        <ArrowUpDown className="h-3 w-3" />
                        {sortField === field && (
                          <span className="text-primary text-[10px]">{sortDir === "asc" ? "↑" : "↓"}</span>
                        )}
                      </span>
                    </th>
                  ))}
                  <th className="text-left px-4 py-3 font-medium text-muted-foreground">Status</th>
                  <th className="px-4 py-3 font-medium text-muted-foreground text-right">Actions</th>
                </tr>
              </thead>
              <tbody>
                {filtered.map((doc) => (
                  <tr
                    key={doc.document_id}
                    className={`border-b last:border-0 hover:bg-muted/30 transition-colors ${
                      activeDocument?.document_id === doc.document_id ? "bg-primary/5" : ""
                    }`}
                  >
                    <td className="px-4 py-3">
                      <div className="flex items-center gap-2">
                        <FileText className="h-4 w-4 text-muted-foreground shrink-0" />
                        <div>
                          <p className="font-medium truncate max-w-[200px]">{doc.filename}</p>
                          {activeDocument?.document_id === doc.document_id && (
                            <span className="text-[10px] text-primary font-medium">Active</span>
                          )}
                        </div>
                      </div>
                    </td>
                    <td className="px-4 py-3 text-muted-foreground whitespace-nowrap">
                      {formatDate(doc.uploaded_at)}
                    </td>
                    <td className="px-4 py-3">{doc.page_count}</td>
                    <td className="px-4 py-3">
                      <div>
                        <span>{doc.chunk_count.toLocaleString()}</span>
                        {doc.embedding_count != null && doc.embedding_count > 0 && (
                          <span className="text-[10px] text-muted-foreground ml-1">
                            ({doc.embedding_count} vectors)
                          </span>
                        )}
                      </div>
                      {(doc.image_count ?? 0) > 0 && (
                        <div className="flex items-center gap-1 text-[10px] text-muted-foreground mt-0.5">
                          <Image className="h-3 w-3" />
                          {doc.image_count} images
                        </div>
                      )}
                    </td>
                    <td className="px-4 py-3 text-muted-foreground">{formatBytes(doc.size_bytes)}</td>
                    <td className="px-4 py-3">
                      <span
                        className={`inline-flex items-center gap-1 rounded-full px-2 py-0.5 text-[10px] font-medium ${
                          doc.status === "indexed"
                            ? "bg-green-100 text-green-700 dark:bg-green-900/30 dark:text-green-400"
                            : doc.status === "processing"
                              ? "bg-yellow-100 text-yellow-700 dark:bg-yellow-900/30 dark:text-yellow-400"
                              : "bg-red-100 text-red-700 dark:bg-red-900/30 dark:text-red-400"
                        }`}
                      >
                        {doc.status === "indexed" && <CheckCircle2 className="h-3 w-3" />}
                        {doc.status}
                      </span>
                    </td>
                    <td className="px-4 py-3 text-right">
                      <div className="flex items-center gap-1 justify-end">
                        {activeDocument?.document_id !== doc.document_id && (
                          <Button
                            variant="ghost"
                            size="sm"
                            onClick={() => setActiveDocument(doc.document_id)}
                            className="text-xs"
                          >
                            Set Active
                          </Button>
                        )}

                        {confirmDeleteId === doc.document_id ? (
                          <div className="flex items-center gap-1">
                            <Button
                              variant="destructive"
                              size="sm"
                              onClick={() => handleDelete(doc.document_id, doc.filename)}
                              disabled={deletingId === doc.document_id}
                              className="text-xs"
                            >
                              {deletingId === doc.document_id ? (
                                <Loader2 className="h-3 w-3 animate-spin" />
                              ) : (
                                "Confirm"
                              )}
                            </Button>
                            <Button
                              variant="ghost"
                              size="sm"
                              onClick={() => setConfirmDeleteId(null)}
                              className="text-xs"
                            >
                              Cancel
                            </Button>
                          </div>
                        ) : (
                          <Button
                            variant="ghost"
                            size="sm"
                            onClick={() => setConfirmDeleteId(doc.document_id)}
                            className="text-xs text-muted-foreground hover:text-red-600"
                          >
                            <Trash2 className="h-3.5 w-3.5" />
                          </Button>
                        )}
                      </div>
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        </div>
      )}
    </div>
  );
}
