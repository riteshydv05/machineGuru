import { Upload, FileText } from "lucide-react";
import { type DragEvent, useRef, useState } from "react";
import { cn } from "@/utils/cn";

interface Props {
  onFile: (file: File) => void;
  disabled?: boolean;
}

export function FileUploader({ onFile, disabled }: Props) {
  const inputRef = useRef<HTMLInputElement>(null);
  const [dragging, setDragging] = useState(false);

  const handleFile = (file: File) => {
    const ext = file.name.split(".").pop()?.toLowerCase();
    if (!ext || !["pdf", "txt", "docx"].includes(ext)) return;
    onFile(file);
  };

  const onDrop = (e: DragEvent) => {
    e.preventDefault();
    setDragging(false);
    const file = e.dataTransfer.files[0];
    if (file) handleFile(file);
  };

  const onDragOver = (e: DragEvent) => {
    e.preventDefault();
    setDragging(true);
  };

  return (
    <div
      onDrop={onDrop}
      onDragOver={onDragOver}
      onDragLeave={() => setDragging(false)}
      onClick={() => inputRef.current?.click()}
      className={cn(
        "flex cursor-pointer flex-col items-center justify-center gap-3 rounded-lg border-2 border-dashed p-12 transition-colors",
        dragging
          ? "border-primary bg-primary/5"
          : "border-muted-foreground/25 hover:border-muted-foreground/50",
        disabled && "pointer-events-none opacity-50",
      )}
    >
      <input
        ref={inputRef}
        type="file"
        accept=".pdf,.txt,.docx"
        className="hidden"
        onChange={(e) => {
          const file = e.target.files?.[0];
          if (file) handleFile(file);
        }}
        disabled={disabled}
      />
      <div className="rounded-full bg-muted p-4">
        {dragging ? (
          <FileText className="h-8 w-8 text-primary" />
        ) : (
          <Upload className="h-8 w-8 text-muted-foreground" />
        )}
      </div>
      <div className="text-center">
        <p className="font-medium">
          {dragging ? "Drop your file here" : "Upload a document"}
        </p>
        <p className="mt-1 text-sm text-muted-foreground">
          PDF, TXT, or DOCX — max 50 MB
        </p>
      </div>
    </div>
  );
}
