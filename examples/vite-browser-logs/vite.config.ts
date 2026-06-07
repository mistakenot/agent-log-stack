import { defineConfig } from "vite";

const agentLogsProxy = {
  "/__agent_logs/browser": {
    target: "http://127.0.0.1:8688",
    changeOrigin: true,
    rewrite: (path: string) =>
      path.replace("/__agent_logs/browser", "/ingest/browser"),
  },
};

export default defineConfig({
  server: {
    proxy: agentLogsProxy,
  },
  preview: {
    proxy: agentLogsProxy,
  },
});
