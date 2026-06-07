# @agent-logs/example-vite-browser-logs

Minimal Vite app demonstrating browser log capture via the agent-logs stack.

## Usage

```bash
# Start the agent-logs stack first
cd ../.. && ./start.sh

# Install dependencies and run the example
npm install
npm run dev
```

Open the browser and logs will be emitted automatically on page load.

## What it demonstrates

- `createLogger` with `app` and `screenId` config
- `log.info()`, `log.warn()`, `log.error()` calls
- Automatic capture of unhandled errors via global error handler
- Vite dev server proxy forwarding `/__agent_logs/browser` to Vector ingest

## Verifying logs

```bash
curl -s 'http://127.0.0.1:9428/select/logsql/query' \
  -d 'query={app="vite-example",source="browser"} | limit 10'
```
