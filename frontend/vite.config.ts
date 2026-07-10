import react from "@vitejs/plugin-react";
import { defineConfig, loadEnv } from "vite";
import path from "path";

export default defineConfig(({ mode }) => {
  // Load .env from project root (one level up from frontend/)
  const env = loadEnv(mode, path.resolve(__dirname, ".."), "");

  // Backend port: read from BACKEND_PORT in root .env, fallback to 8001
  const backendPort = env.BACKEND_PORT || "8001";
  const backendUrl = `http://localhost:${backendPort}`;

  return {
    plugins: [react()],
    resolve: {
      alias: {
        "@": path.resolve(__dirname, "./src"),
      },
    },
    server: {
      port: parseInt(env.FRONTEND_PORT || "5173"),
      proxy: {
        // All /api/* requests are forwarded to the FastAPI backend.
        // This proxy is ONLY active in dev mode (npm run dev).
        // In production, nginx handles the proxy (see nginx.conf).
        "/api": {
          target: backendUrl,
          changeOrigin: true,
        },
      },
    },
  };
});
