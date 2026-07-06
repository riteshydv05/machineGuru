import { CheckCircle2, Loader2, XCircle } from "lucide-react";
import { Progress } from "@/components/ui/progress";

interface Props {
  filename: string;
  progress: number;
  status: "uploading" | "processing" | "done" | "error";
  error?: string;
}

export function UploadProgress({ filename, progress, status, error }: Props) {
  return (
    <div className="space-y-3 rounded-lg border p-4">
      <div className="flex items-center justify-between">
        <span className="truncate text-sm font-medium">{filename}</span>
        {status === "done" && (
          <CheckCircle2 className="h-5 w-5 text-green-500" />
        )}
        {status === "error" && <XCircle className="h-5 w-5 text-red-500" />}
        {(status === "uploading" || status === "processing") && (
          <Loader2 className="h-5 w-5 animate-spin text-muted-foreground" />
        )}
      </div>

      <Progress value={progress} />

      {status === "uploading" && (
        <p className="text-xs text-muted-foreground">Uploading... {progress}%</p>
      )}
      {status === "processing" && (
        <p className="text-xs text-muted-foreground">Processing document...</p>
      )}
      {status === "done" && (
        <p className="text-xs text-green-500">Upload complete</p>
      )}
      {status === "error" && (
        <p className="text-xs text-red-500">{error || "Upload failed"}</p>
      )}
    </div>
  );
}
