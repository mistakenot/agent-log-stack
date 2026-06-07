import { createLogger } from "../../../packages/browser-logger/src/index";

// Create a logger instance with screen and route metadata
const log = createLogger({
  app: "vite-example",
  screenId: "home",
});

// Emit test logs on page load (useful for E2E testing)
log.info("Page loaded successfully", { route: "/", loadTime: Date.now() });
log.warn("This is a warning demonstration", { component: "main" });
log.error("Simulated error for testing", { code: "DEMO_ERROR" });

// Update status element to indicate logs were sent
const status = document.getElementById("status");
if (status) {
  status.textContent = "Logs emitted (info, warn, error). Check Vector ingest.";
}

// Throw an unhandled error to test global error capture
setTimeout(() => {
  throw new Error("Unhandled error for testing global capture");
}, 100);
