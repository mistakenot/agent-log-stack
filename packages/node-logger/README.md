# @agent-logs/node-logger

Node.js logging helper that wraps `console.*` and emits structured JSON to the agent-logs stack.

## Usage

```typescript
import { createLogger } from "@agent-logs/node-logger";

const logger = createLogger({
  app: "my-app",
  service: "api",
});

logger.info("Server started on port", 3000);
logger.warn("Cache miss", { key: "user:123" });
logger.error("Failed to connect to database");
```

Output still goes to stdout/stderr via the original console methods. Structured logs are POSTed (fire-and-forget) to the agent-logs Vector ingest endpoint.

## Configuration

```typescript
interface LoggerConfig {
  url?: string;       // Default: AGENT_LOGS_URL env or http://127.0.0.1:8688
  app: string;        // Application name (required)
  service?: string;   // Service name (default: SERVICE env or "default")
  source?: string;    // Log source (default: "backend")
  agentId?: string;   // Default: AGENT_ID env
  runId?: string;     // Default: RUN_ID env
  worktree?: string;  // Default: WORKTREE env
}
```

## Build

```bash
npm install
npm run build
```
