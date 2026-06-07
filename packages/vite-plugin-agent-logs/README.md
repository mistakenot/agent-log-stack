# @agent-logs/vite-plugin

Vite plugin that configures the `/__agent_logs/browser` proxy and optionally injects the browser-logger in dev mode.

## Installation

```bash
npm install @agent-logs/vite-plugin --save-dev
```

## Usage

```ts
// vite.config.ts
import { defineConfig } from "vite";
import agentLogs from "@agent-logs/vite-plugin";

export default defineConfig({
  plugins: [
    agentLogs({
      // target: "http://127.0.0.1:8688", // defaults to AGENT_LOGS_URL env or 127.0.0.1:8688
      // app: "my-app",                    // app name for browser-logger
      // inject: true,                     // inject browser-logger script tag in dev HTML
    }),
  ],
});
```

## Options

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `target` | `string` | `process.env.AGENT_LOGS_URL` or `http://127.0.0.1:8688` | Vector ingest endpoint URL |
| `app` | `string` | `"app"` | Application name passed to browser-logger |
| `inject` | `boolean` | `false` | Inject browser-logger script tag into HTML in dev mode |

## How it works

The plugin adds a Vite dev server proxy rule:

```
/__agent_logs/browser  -->  {target}/ingest/browser
```

When `inject: true`, it uses the `transformIndexHtml` hook to add a `<script type="module">` tag that imports and initializes `@agent-logs/browser-logger`.

## Peer Dependencies

- `vite` ^5.0.0 || ^6.0.0
- `@agent-logs/browser-logger` (when using `inject: true`)
