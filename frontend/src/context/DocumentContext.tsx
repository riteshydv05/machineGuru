import {
  createContext,
  useCallback,
  useContext,
  useEffect,
  useState,
  type ReactNode,
} from "react";
import {
  fetchDocuments,
  fetchActiveDocument,
  setActiveDocument as apiSetActive,
  deleteDocument as apiDeleteDoc,
} from "@/services/api";
import type { DocumentInfo } from "@/types";

export type QueryMode = "current" | "all";

interface DocumentContextValue {
  documents: DocumentInfo[];
  activeDocument: DocumentInfo | null;
  queryMode: QueryMode;
  totalDocuments: number;
  loading: boolean;
  setQueryMode: (mode: QueryMode) => void;
  setActiveDocument: (id: string) => Promise<void>;
  deleteDocument: (id: string) => Promise<void>;
  refresh: () => Promise<void>;
}

const DocumentContext = createContext<DocumentContextValue>({
  documents: [],
  activeDocument: null,
  queryMode: "current",
  totalDocuments: 0,
  loading: true,
  setQueryMode: () => {},
  setActiveDocument: async () => {},
  deleteDocument: async () => {},
  refresh: async () => {},
});

export function useDocuments() {
  return useContext(DocumentContext);
}

export function DocumentProvider({ children }: { children: ReactNode }) {
  const [documents, setDocuments] = useState<DocumentInfo[]>([]);
  const [activeDocument, setActiveDoc] = useState<DocumentInfo | null>(null);
  const [queryMode, setQueryMode] = useState<QueryMode>("current");
  const [loading, setLoading] = useState(true);

  const refresh = useCallback(async () => {
    try {
      const [listRes, active] = await Promise.all([
        fetchDocuments(),
        fetchActiveDocument(),
      ]);
      setDocuments(listRes.documents);
      setActiveDoc(active);
    } catch {
      // Backend might not be running yet
    } finally {
      setLoading(false);
    }
  }, []);

  useEffect(() => {
    refresh();
    // Refresh every 30 seconds
    const id = setInterval(refresh, 30_000);
    return () => clearInterval(id);
  }, [refresh]);

  const setActiveDocument = useCallback(async (docId: string) => {
    const doc = await apiSetActive(docId);
    if (doc) {
      setActiveDoc(doc);
    }
  }, []);

  const deleteDocument = useCallback(async (docId: string) => {
    await apiDeleteDoc(docId);
    await refresh();
  }, [refresh]);

  return (
    <DocumentContext.Provider
      value={{
        documents,
        activeDocument,
        queryMode,
        totalDocuments: documents.length,
        loading,
        setQueryMode,
        setActiveDocument,
        deleteDocument,
        refresh,
      }}
    >
      {children}
    </DocumentContext.Provider>
  );
}
