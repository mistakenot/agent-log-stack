#!/usr/bin/env bash
set -euo pipefail

# discover-app.sh — Detect project tooling, configs, and log files in a directory.
# Outputs JSON suitable for agent consumption.

show_help() {
  cat <<'EOF'
Usage: discover-app.sh [OPTIONS]

Scan a directory for package managers, framework configs, process managers,
Docker Compose files, and likely log files.

Options:
  --dir PATH    Directory to scan (default: current directory)
  --pretty      Pretty-print JSON output (uses jq if available)
  --help        Show this help message

Environment variables:
  AGENT_LOGS_URL         (default http://127.0.0.1:4318)
  VICTORIA_LOGS_URL      (default http://127.0.0.1:9428)
  VICTORIA_METRICS_URL   (default http://127.0.0.1:8428)

Output (JSON):
  {
    "package_managers": [...],
    "vite_configs": [...],
    "pm2_configs": [...],
    "compose_files": [...],
    "log_files": [...]
  }

Exit codes:
  0  Always (empty results if nothing found)
EOF
}

SCAN_DIR="."
PRETTY=false

while [[ $# -gt 0 ]]; do
  case "$1" in
    --help)
      show_help
      exit 0
      ;;
    --dir)
      SCAN_DIR="$2"
      shift 2
      ;;
    --pretty)
      PRETTY=true
      shift
      ;;
    *)
      echo "Unknown option: $1" >&2
      echo "Run with --help for usage." >&2
      exit 1
      ;;
  esac
done

# Resolve to absolute path
SCAN_DIR="$(cd "$SCAN_DIR" && pwd)"

# --- Detection functions ---

json_array_from_lines() {
  local first=true
  printf '['
  while IFS= read -r line; do
    [[ -z "$line" ]] && continue
    if [[ "$first" == true ]]; then
      first=false
    else
      printf ','
    fi
    # Escape backslashes and quotes for valid JSON
    line="${line//\\/\\\\}"
    line="${line//\"/\\\"}"
    printf '"%s"' "$line"
  done
  printf ']'
}

detect_package_managers() {
  local results=""
  [[ -f "$SCAN_DIR/package.json" ]] && results+="$SCAN_DIR/package.json"$'\n'
  [[ -f "$SCAN_DIR/requirements.txt" ]] && results+="$SCAN_DIR/requirements.txt"$'\n'
  [[ -f "$SCAN_DIR/pyproject.toml" ]] && results+="$SCAN_DIR/pyproject.toml"$'\n'
  [[ -f "$SCAN_DIR/go.mod" ]] && results+="$SCAN_DIR/go.mod"$'\n'
  [[ -f "$SCAN_DIR/Cargo.toml" ]] && results+="$SCAN_DIR/Cargo.toml"$'\n'
  echo -n "$results" | json_array_from_lines
}

detect_vite_configs() {
  local results=""
  [[ -f "$SCAN_DIR/vite.config.ts" ]] && results+="$SCAN_DIR/vite.config.ts"$'\n'
  [[ -f "$SCAN_DIR/vite.config.js" ]] && results+="$SCAN_DIR/vite.config.js"$'\n'
  echo -n "$results" | json_array_from_lines
}

detect_pm2_configs() {
  local results=""
  [[ -f "$SCAN_DIR/ecosystem.config.js" ]] && results+="$SCAN_DIR/ecosystem.config.js"$'\n'
  [[ -f "$SCAN_DIR/pm2.json" ]] && results+="$SCAN_DIR/pm2.json"$'\n'
  echo -n "$results" | json_array_from_lines
}

detect_compose_files() {
  local results=""
  [[ -f "$SCAN_DIR/docker-compose.yml" ]] && results+="$SCAN_DIR/docker-compose.yml"$'\n'
  [[ -f "$SCAN_DIR/docker-compose.yaml" ]] && results+="$SCAN_DIR/docker-compose.yaml"$'\n'
  [[ -f "$SCAN_DIR/compose.yml" ]] && results+="$SCAN_DIR/compose.yml"$'\n'
  [[ -f "$SCAN_DIR/compose.yaml" ]] && results+="$SCAN_DIR/compose.yaml"$'\n'
  echo -n "$results" | json_array_from_lines
}

detect_log_files() {
  local results=""

  # PM2 logs
  if [[ -d "$HOME/.pm2/logs" ]]; then
    while IFS= read -r -d '' f; do
      results+="$f"$'\n'
    done < <(find "$HOME/.pm2/logs" -name "*.log" -print0 2>/dev/null || true)
  fi

  # Common log directories relative to scan dir
  local log_dirs=("logs" "log" ".logs" "tmp/logs")
  for dir in "${log_dirs[@]}"; do
    if [[ -d "$SCAN_DIR/$dir" ]]; then
      while IFS= read -r -d '' f; do
        results+="$f"$'\n'
      done < <(find "$SCAN_DIR/$dir" -name "*.log" -print0 2>/dev/null || true)
    fi
  done

  # /var/log common app logs (non-recursive, only if accessible)
  if [[ -d /var/log ]]; then
    for f in /var/log/app.log /var/log/node.log /var/log/pm2.log; do
      [[ -f "$f" ]] && results+="$f"$'\n'
    done
  fi

  echo -n "$results" | json_array_from_lines
}

# --- Build output ---

output=$(printf '{"package_managers":%s,"vite_configs":%s,"pm2_configs":%s,"compose_files":%s,"log_files":%s}' \
  "$(detect_package_managers)" \
  "$(detect_vite_configs)" \
  "$(detect_pm2_configs)" \
  "$(detect_compose_files)" \
  "$(detect_log_files)")

if [[ "$PRETTY" == true ]]; then
  if command -v jq &>/dev/null; then
    echo "$output" | jq .
  else
    echo "$output"
  fi
else
  echo "$output"
fi

exit 0
