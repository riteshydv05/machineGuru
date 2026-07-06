import { Outlet } from "react-router-dom";
import { Sidebar } from "./Sidebar";

export function AppLayout() {
  return (
    <div className="flex h-screen overflow-hidden">
      {/* Desktop sidebar */}
      <Sidebar />

      {/* Main content area */}
      <main className="flex-1 flex flex-col overflow-hidden bg-background">
        {/* Mobile: push content below the fixed top bar (h-[57px]) */}
        <div className="block md:hidden h-[57px] shrink-0" />

        <div className="flex-1 overflow-auto p-4 md:p-6 flex flex-col">
          <Outlet />
        </div>
      </main>
    </div>
  );
}
