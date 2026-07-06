import { memo } from "react";
import { Bot, User } from "lucide-react";
import { cn } from "@/utils/cn";
import type { ChatMessage as ChatMessageType } from "@/types";
import { CitationRenderer } from "@/components/citations/CitationRenderer";

interface Props {
  message: ChatMessageType;
}

function ChatMessageInner({ message }: Props) {
  const isUser = message.role === "user";
  return (
    <div
      className={cn(
        "flex gap-3",
        isUser ? "flex-row-reverse" : "flex-row",
      )}
    >
      <div
        className={cn(
          "flex h-8 w-8 shrink-0 items-center justify-center rounded-full",
          isUser ? "bg-primary text-primary-foreground" : "bg-muted",
        )}
      >
        {isUser ? <User className="h-4 w-4" /> : <Bot className="h-4 w-4" />}
      </div>

      <div
        className={cn(
          "max-w-[80%] space-y-2 rounded-lg px-4 py-3",
          isUser
            ? "bg-primary text-primary-foreground"
            : "bg-muted text-foreground",
        )}
      >
        {isUser ? (
          <p className="prose prose-sm dark:prose-invert max-w-none whitespace-pre-wrap">
            {message.content}
          </p>
        ) : (
          <CitationRenderer
            content={message.content}
            sources={message.sources ?? []}
          />
        )}
      </div>
    </div>
  );
}

export const ChatMessage = memo(ChatMessageInner);
