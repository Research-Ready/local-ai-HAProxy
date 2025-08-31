#!/usr/bin/env bash
# ai_stack_health.sh — quick diagnostics for local-ai-packaged services behind HAProxy
# Checks localhost ports + basic HTTP responses. Accepts 2xx/3xx as healthy.
# Usage: ./ai_stack_health.sh [--host 127.0.0.1] [--timeout 4] [--retries 20] [--sleep 2]

set -euo pipefail

HOST="127.0.0.1"
TIMEOUT=4
RETRIES=20
SLEEP=2

while [[ $# -gt 0 ]]; do
  case "$1" in
    --host)    HOST="${2:-127.0.0.1}"; shift 2 ;;
    --timeout) TIMEOUT="${2:-4}"; shift 2 ;;
    --retries) RETRIES="${2:-20}"; shift 2 ;;
    --sleep)   SLEEP="${2:-2}"; shift 2 ;;
    -h|--help)
      echo "Usage: $0 [--host IP] [--timeout SEC] [--retries N] [--sleep SEC]"
      exit 0
      ;;
    *) echo "Unknown arg: $1"; exit 2 ;;
  esac
done

# Colors if TTY
if [[ -t 1 ]]; then
  GREEN="\033[32m"; YELLOW="\033[33m"; RED="\033[31m"; CYAN="\033[36m"; BOLD="\033[1m"; RESET="\033[0m"
else
  GREEN=""; YELLOW=""; RED=""; CYAN=""; BOLD=""; RESET=""
fi

ok()   { echo -e "${GREEN}✔${RESET} $*"; }
warn() { echo -e "${YELLOW}⚠${RESET} $*"; }
err()  { echo -e "${RED}✘${RESET} $*"; }
info() { echo -e "${CYAN}i${RESET} $*"; }

# Service map: name|port|path-to-ping
readarray -t SERVICES <<'EOF'
OpenWebUI|8080|/
n8n|5678|/rest/ping
Flowise|3001|/
Langfuse|3010|/
SearXNG|8081|/
Qdrant|6333|/collections
Neo4j|7474|/
EOF

tcp_check() {
  local host="$1" port="$2"
  (echo >/dev/tcp/"$host"/"$port") >/dev/null 2>&1
}

http_status() {
  local url="$1" timeout="$2"
  curl -sS -o /dev/null -m "$timeout" -w "%{http_code}" "$url" || echo "000"
}

wait_for_tcp() {
  local name="$1" host="$2" port="$3" retries="$4" sleep_s="$5"
  for i in $(seq 1 "$retries"); do
    if tcp_check "$host" "$port"; then
      return 0
    fi
    sleep "$sleep_s"
  done
  return 1
}

divider() { printf '%*s\n' "${COLUMNS:-80}" '' | tr ' ' '─'; }

echo -e "${BOLD}AI Stack Internal Diagnostics${RESET} (host: ${BOLD}${HOST}${RESET}, timeout: ${TIMEOUT}s)"
divider

declare -i FAILS=0
declare -a REPORT=()

for line in "${SERVICES[@]}"; do
  IFS='|' read -r NAME PORT PATH <<<"$line"
  URL="http://${HOST}:${PORT}${PATH}"
  printf "%-10s → %s " "$NAME" "$URL"

  if ! wait_for_tcp "$NAME" "$HOST" "$PORT" "$RETRIES" "$SLEEP"; then
    err "TCP closed on ${HOST}:${PORT}"
    REPORT+=("$(printf '%-10s : %s' "$NAME" "DOWN (TCP closed)")")
    ((FAILS++))
    continue
  fi

  STATUS=$(http_status "$URL" "$TIMEOUT")
  if [[ "$STATUS" =~ ^2..$ || "$STATUS" =~ ^3..$ ]]; then
    ok "HTTP ${STATUS}"
    REPORT+=("$(printf '%-10s : %s' "$NAME" "OK (HTTP ${STATUS})")")
  else
    warn "HTTP ${STATUS}"
    REPORT+=("$(printf '%-10s : %s' "$NAME" "WARN (HTTP ${STATUS})")")
    # Special-case deeper checks
    case "$NAME" in
      Qdrant)
        # try health-ish endpoint
        HEALTH=$(http_status "http://${HOST}:${PORT}/readyz" "$TIMEOUT")
        [[ "$HEALTH" =~ ^2..$ ]] && ok "Qdrant /readyz ${HEALTH}" || true
        ;;
      n8n)
        # /rest/ping is already used; nothing extra
        ;;
    esac
  fi
done

divider
echo -e "${BOLD}Summary:${RESET}"
for r in "${REPORT[@]}"; do echo " • $r"; done

if (( FAILS > 0 )); then
  echo
  err "Failures: ${FAILS}"
  exit 1
else
  echo
  ok "All services reachable (2xx/3xx considered healthy)."
  exit 0
fi
