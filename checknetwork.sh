```bash
#!/usr/bin/env bash
# ai_stack_diag.sh — robust internal health diagnostics for local-ai-packaged
# - No prompts, no assumptions; checks keep going even if some tools/ports fail
# - Uses curl for HTTP; falls back to nc or /dev/tcp for raw TCP when needed
# - Configure via env vars (no flags needed):
#     HOST=127.0.0.1 RETRIES=20 SLEEP=2 CONNECT_TIMEOUT=3 HTTP_TIMEOUT=5 ./ai_stack_diag.sh

# ---------- Config (env-overridable) ----------
HOST="${HOST:-127.0.0.1}"
RETRIES="${RETRIES:-20}"              # how many times to retry a service before giving up
SLEEP="${SLEEP:-2}"                   # seconds between retries
CONNECT_TIMEOUT="${CONNECT_TIMEOUT:-3}"  # TCP/HTTP connect timeout per try
HTTP_TIMEOUT="${HTTP_TIMEOUT:-5}"        # total HTTP time per try

# ---------- Tool detection ----------
has_cmd() { command -v "$1" >/dev/null 2>&1; }
HAS_CURL=0; has_cmd curl && HAS_CURL=1
HAS_NC=0;   has_cmd nc && HAS_NC=1
HAS_TIMEOUT=0; has_cmd timeout && HAS_TIMEOUT=1

# ---------- Output helpers (no color to avoid weird shells) ----------
ok()   { printf "OK     - %s\n" "$*"; }
warn() { printf "WARN   - %s\n" "$*"; }
fail() { printf "FAIL   - %s\n" "$*"; }
info() { printf "INFO   - %s\n" "$*"; }
line() { printf -- "-----------------------------------------------\n"; }

# ---------- TCP check with fallbacks ----------
tcp_check_once() {
  # $1 host, $2 port
  local h="$1" p="$2"
  # Prefer nc if present
  if [ "$HAS_NC" -eq 1 ]; then
    nc -z -w "$CONNECT_TIMEOUT" "$h" "$p" >/dev/null 2>&1
    return $?
  fi
  # Try /dev/tcp with timeout if available
  if [ "$HAS_TIMEOUT" -eq 1 ]; then
    timeout "$CONNECT_TIMEOUT" bash -c ">/dev/tcp/$h/$p" >/dev/null 2>&1
    return $?
  fi
  # Last resort: try HTTP connect (may fail for non-HTTP ports, but better than nothing)
  if [ "$HAS_CURL" -eq 1 ]; then
    curl -sS -o /dev/null --connect-timeout "$CONNECT_TIMEOUT" "http://$h:$p/" >/dev/null 2>&1
    return $?
  fi
  # No method available
  return 2
}

tcp_check_retry() {
  # $1 host, $2 port, $3 name
  local h="$1" p="$2" name="$3" i=1
  while [ "$i" -le "$RETRIES" ]; do
    if tcp_check_once "$h" "$p"; then
      return 0
    fi
    sleep "$SLEEP"
    i=$((i+1))
  done
  return 1
}

# ---------- HTTP check (2xx/3xx considered healthy) ----------
http_check_once() {
  # $1 url
  local url="$1" code="000"
  if [ "$HAS_CURL" -ne 1 ]; then
    echo "$code"
    return 0
  fi
  code=$(curl -sS -o /dev/null -m "$HTTP_TIMEOUT" --connect-timeout "$CONNECT_TIMEOUT" -w "%{http_code}" "$url" 2>/dev/null || echo "000")
  echo "$code"
}

http_check_retry() {
  # $1 url
  local url="$1" i=1 code
  while [ "$i" -le "$RETRIES" ]; do
    code=$(http_check_once "$url")
    case "$code" in
      2??|3??) echo "$code"; return 0 ;;
      *) sleep "$SLEEP" ;;
    esac
    i=$((i+1))
  done
  echo "$code"
  return 1
}

# ---------- Service list: name|port|path|check_mode ----------
# check_mode: http or tcp
read -r -d '' SERVICES <<'EOF'
OpenWebUI|8080|/|http
n8n|5678|/rest/ping|http
Flowise|3001|/|http
Langfuse|3010|/|http
SearXNG|8081|/|http
Qdrant|6333|/collections|http
Neo4j|7474|/|http
Neo4jBolt|7687|/|tcp
EOF

# ---------- Run ----------
printf "AI Stack Internal Diagnostics (host: %s, retries: %s, sleep: %ss, timeouts: connect=%ss http=%ss)\n" "$HOST" "$RETRIES" "$SLEEP" "$CONNECT_TIMEOUT" "$HTTP_TIMEOUT"
line
[ "$HAS_CURL" -eq 1 ] && info "curl detected" || warn "curl NOT found (HTTP checks may be limited)"
[ "$HAS_NC" -eq 1 ]   && info "nc detected"   || warn "nc NOT found (raw TCP checks use fallbacks)"
[ "$HAS_TIMEOUT" -eq 1 ] && info "timeout detected" || warn "timeout NOT found (raw TCP fallbacks may block longer)"
line

FAILS=0
WARNS=0

# Iterate services
# Use while-read to avoid seq; robust even in BusyBox environments
IFS='
'
for entry in $SERVICES; do
  name=$(printf "%s" "$entry" | awk -F'|' '{print $1}')
  port=$(printf "%s" "$entry" | awk -F'|' '{print $2}')
  path=$(printf "%s" "$entry" | awk -F'|' '{print $3}')
  mode=$(printf "%s" "$entry" | awk -F'|' '{print $4}')

  url="http://${HOST}:${port}${path}"
  printf "%-10s -> %s\n" "$name" "$url"

  if [ "$mode" = "http" ]; then
    # First ensure TCP opens (fast fail if impossible)
    if tcp_check_retry "$HOST" "$port" "$name"; then
      code=$(http_check_retry "$url")
      if printf "%s" "$code" | grep -Eq '^(2|3)[0-9][0-9]$'; then
        ok "$name HTTP $code"
      else
        warn "$name HTTP $code"
        WARNS=$((WARNS+1))
      fi
    else
      fail "$name TCP CLOSED on ${HOST}:${port}"
      FAILS=$((FAILS+1))
    fi
  else
    # Pure TCP checks (e.g., Neo4j Bolt)
    if tcp_check_retry "$HOST" "$port" "$name"; then
      ok "$name TCP OPEN on ${HOST}:${port}"
    else
      fail "$name TCP CLOSED on ${HOST}:${port}"
      FAILS=$((FAILS+1))
    fi
  fi
  line
done

# ---------- Summary ----------
printf "Summary: FAIL=%d  WARN=%d\n" "$FAILS" "$WARNS"
if [ "$FAILS" -gt 0 ]; then
  exit 1
fi
exit 0
```
