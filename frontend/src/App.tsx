import { Route, Routes } from "react-router-dom";
import { ThemeProvider } from "@/context/ThemeContext";
import { DocumentProvider } from "@/context/DocumentContext";
import { AppLayout } from "@/components/layout/AppLayout";
import { DashboardPage } from "@/pages/DashboardPage";
import { ChatPage } from "@/pages/ChatPage";
import { UploadPage } from "@/pages/UploadPage";
import { DocumentsPage } from "@/pages/DocumentsPage";
import { HistoryPage } from "@/pages/HistoryPage";
import { SettingsPage } from "@/pages/SettingsPage";

function App() {
  return (
    <ThemeProvider>
      <DocumentProvider>
        <Routes>
          <Route element={<AppLayout />}>
            <Route path="/" element={<DashboardPage />} />
            <Route path="/upload" element={<UploadPage />} />
            <Route path="/documents" element={<DocumentsPage />} />
            <Route path="/chat" element={<ChatPage />} />
            <Route path="/history" element={<HistoryPage />} />
            <Route path="/settings" element={<SettingsPage />} />
          </Route>
        </Routes>
      </DocumentProvider>
    </ThemeProvider>
  );
}

export default App;
