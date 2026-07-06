import { useState } from "react";
import { BarChart3, History, MessageSquare, Menu, Settings, Upload, X } from "lucide-react";
import { NavLink } from "react-router-dom";
import { cn } from "@/utils/cn";
import { ThemeToggle } from "./ThemeToggle";

const links = [
  { to: "/", label: "Dashboard", icon: BarChart3 },
  { to: "/upload", label: "Upload", icon: Upload },
  { to: "/chat", label: "Chat", icon: MessageSquare },
  { to: "/history", label: "History", icon: History },
  { to: "/settings", label: "Settings", icon: Settings },
];

function NavLinks({ onNavigate }: { onNavigate?: () => void }) {
  return (
    <nav className="flex-1 space-y-1 p-4">
      {links.map(({ to, label, icon: Icon }) => (
        <NavLink
          key={to}
          to={to}
          end={to === "/"}
          onClick={onNavigate}
          className={({ isActive }) =>
            cn(
              "flex items-center gap-3 rounded-lg px-3 py-2.5 text-sm font-medium transition-colors",
              isActive
                ? "bg-primary text-primary-foreground"
                : "text-muted-foreground hover:bg-accent hover:text-accent-foreground",
            )
          }
        >
          <Icon className="h-4 w-4 shrink-0" />
          {label}
        </NavLink>
      ))}
    </nav>
  );
}

function SidebarContent({ onNavigate }: { onNavigate?: () => void }) {
  return (
    <>
      <div className="flex items-center gap-2 border-b px-6 py-4">
        <div className="flex h-8 w-8 items-center justify-center rounded-lg bg-primary text-sm font-bold text-primary-foreground">
          MG
        </div>
        <span className="text-lg font-semibold">MachineGuru</span>
      </div>

      <NavLinks onNavigate={onNavigate} />

      <div className="flex items-center justify-between border-t p-4">
        <span className="text-xs text-muted-foreground">v0.1.0</span>
        <ThemeToggle />
      </div>
    </>
  );
}

export function Sidebar() {
  const [mobileOpen, setMobileOpen] = useState(false);

  return (
    <>
      {/* ─── Desktop sidebar (hidden on mobile) ─── */}
      <aside className="hidden md:flex h-full w-64 shrink-0 flex-col border-r bg-card">
        <SidebarContent />
      </aside>

      {/* ─── Mobile top bar ─── */}
      <div className="flex md:hidden items-center justify-between border-b bg-card px-4 py-3 fixed top-0 left-0 right-0 z-40">
        <div className="flex items-center gap-2">
          <div className="flex h-7 w-7 items-center justify-center rounded-lg bg-primary text-xs font-bold text-primary-foreground">
            MG
          </div>
          <span className="text-base font-semibold">MachineGuru</span>
        </div>
        <div className="flex items-center gap-2">
          <ThemeToggle />
          <button
            onClick={() => setMobileOpen(true)}
            className="rounded-md p-1.5 text-muted-foreground hover:bg-accent hover:text-accent-foreground transition-colors"
            aria-label="Open menu"
          >
            <Menu className="h-5 w-5" />
          </button>
        </div>
      </div>

      {/* ─── Mobile drawer overlay ─── */}
      {mobileOpen && (
        <div
          className="fixed inset-0 z-50 md:hidden"
          onClick={() => setMobileOpen(false)}
        >
          {/* Backdrop */}
          <div className="absolute inset-0 bg-black/50 backdrop-blur-sm" />

          {/* Drawer panel */}
          <aside
            className="absolute left-0 top-0 bottom-0 w-72 flex flex-col bg-card border-r shadow-xl"
            onClick={(e) => e.stopPropagation()}
          >
            <div className="flex items-center justify-between border-b px-6 py-4">
              <div className="flex items-center gap-2">
                <div className="flex h-8 w-8 items-center justify-center rounded-lg bg-primary text-sm font-bold text-primary-foreground">
                  MG
                </div>
                <span className="text-lg font-semibold">MachineGuru</span>
              </div>
              <button
                onClick={() => setMobileOpen(false)}
                className="rounded-md p-1 text-muted-foreground hover:bg-accent hover:text-accent-foreground transition-colors"
                aria-label="Close menu"
              >
                <X className="h-5 w-5" />
              </button>
            </div>

            <NavLinks onNavigate={() => setMobileOpen(false)} />

            <div className="flex items-center justify-between border-t p-4">
              <span className="text-xs text-muted-foreground">v0.1.0</span>
            </div>
          </aside>
        </div>
      )}
    </>
  );
}
