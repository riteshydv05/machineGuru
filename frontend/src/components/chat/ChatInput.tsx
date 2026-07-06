import { Send } from "lucide-react";
import { type FormEvent, useState } from "react";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";

interface Props {
  onSend: (text: string) => void;
  disabled?: boolean;
}

export function ChatInput({ onSend, disabled }: Props) {
  const [text, setText] = useState("");

  const handleSubmit = (e: FormEvent) => {
    e.preventDefault();
    if (!text.trim() || disabled) return;
    onSend(text.trim());
    setText("");
  };

  return (
    <form
      onSubmit={handleSubmit}
      className="flex items-center gap-2 border-t bg-card p-4"
    >
      <Input
        value={text}
        onChange={(e) => setText(e.target.value)}
        placeholder="Ask a question about your documents..."
        disabled={disabled}
        className="flex-1"
      />
      <Button type="submit" size="icon" disabled={disabled || !text.trim()}>
        <Send className="h-4 w-4" />
      </Button>
    </form>
  );
}
