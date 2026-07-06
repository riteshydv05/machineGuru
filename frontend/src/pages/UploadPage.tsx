import { useCallback, useState } from "react";
import { CheckCircle2, FileText } from "lucide-react";
import { uploadFile } from "@/services/api";
import { FileUploader } from "@/components/upload/FileUploader";
import { UploadProgress } from "@/components/upload/UploadProgress";
import type { UploadResponse } from "@/types";

interface UploadItem {
  file: File;
  progress: number;
  status: "uploading" | "processing" | "done" | "error";
  error?: string;
  result?: UploadResponse;
}

export function UploadPage() {
  const [items, setItems] = useState<UploadItem[]>([]);

  const handleFile = useCallback(async (file: File) => {
    const item: UploadItem = { file, progress: 0, status: "uploading" };
    setItems((prev) => [item, ...prev]);

    try {
      const result = await uploadFile(file, (pct) => {
        setItems((prev) =>
          prev.map((it) =>
            it.file === file && it.status === "uploading"
              ? { ...it, progress: pct }
              : it,
          ),
        );
      });

      // mark processing while server crunches chunks
      setItems((prev) =>
        prev.map((it) =>
          it.file === file ? { ...it, status: "processing", progress: 100 } : it,
        ),
      );

      // small delay so user sees the processing state
      await new Promise((r) => setTimeout(r, 600));

      setItems((prev) =>
        prev.map((it) =>
          it.file === file ? { ...it, status: "done", result } : it,
        ),
      );
    } catch (e: unknown) {
      const msg =
        e instanceof Error ? e.message : "Upload failed. Check the server.";
      setItems((prev) =>
        prev.map((it) =>
          it.file === file ? { ...it, status: "error", error: msg } : it,
        ),
      );
    }
  }, []);

  const isUploading = items.some(
    (it) => it.status === "uploading" || it.status === "processing",
  );

  return (
    <div className="max-w-3xl mx-auto space-y-8">
      {/* Header */}
      <div>
        <h1 className="text-3xl font-bold tracking-tight">Upload Documents</h1>
        <p className="mt-1 text-sm text-muted-foreground">
          Upload PDF, TXT, or DOCX files. They will be chunked, embedded, and
          stored in the vector database for querying.
        </p>
      </div>

      {/* Drop zone */}
      <FileUploader onFile={handleFile} disabled={isUploading} />

      {/* Upload queue */}
      {items.length > 0 && (
        <div className="space-y-3">
          <h2 className="text-sm font-medium text-muted-foreground uppercase tracking-wider">
            Upload Queue
          </h2>
          <div className="space-y-3">
            {items.map((item, idx) => (
              <div key={idx} className="space-y-3">
                <UploadProgress
                  filename={item.file.name}
                  progress={item.progress}
                  status={item.status}
                  error={item.error}
                />

                {/* Result summary */}
                {item.status === "done" && item.result && (
                  <div className="rounded-lg border bg-card p-4 text-sm space-y-2">
                    <div className="flex items-center gap-2 font-medium text-green-600 dark:text-green-400">
                      <CheckCircle2 className="h-4 w-4" />
                      Document ingested successfully
                    </div>
                    <dl className="grid grid-cols-2 gap-x-4 gap-y-1.5 text-xs mt-2">
                      {[
                        ["Document ID", item.result.document_id.slice(0, 8) + "…"],
                        ["Pages", item.result.page_count],
                        ["Chunks", item.result.chunk_count],
                        ["Embed dims", item.result.embedding_dimensions],
                        ["Avg chunk len", item.result.average_chunk_length],
                        ["Time", `${item.result.processing_time_seconds.toFixed(2)}s`],
                      ].map(([k, v]) => (
                        <div key={String(k)} className="flex justify-between col-span-1">
                          <dt className="text-muted-foreground">{k}</dt>
                          <dd className="font-medium">{String(v)}</dd>
                        </div>
                      ))}
                    </dl>
                  </div>
                )}
              </div>
            ))}
          </div>
        </div>
      )}

      {/* Empty tip */}
      {items.length === 0 && (
        <div className="rounded-lg border bg-muted/30 p-5 flex items-start gap-3">
          <FileText className="h-5 w-5 text-muted-foreground mt-0.5 shrink-0" />
          <div className="text-sm text-muted-foreground space-y-1">
            <p className="font-medium text-foreground">Supported formats</p>
            <ul className="list-disc list-inside space-y-0.5">
              <li>PDF — multi-page, text-based</li>
              <li>DOCX — Microsoft Word documents</li>
              <li>TXT — plain text files</li>
            </ul>
            <p className="mt-2">Maximum file size: 50 MB</p>
          </div>
        </div>
      )}
    </div>
  );
}
