#!/usr/bin/env bash
set -euo pipefail

SCRIPT_NAME="$(basename "$0")"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_DIR="$SCRIPT_DIR/logs"
DEFAULT_TIMEOUT=15
DEFAULT_BASE_URL="https://notedavidrinaldi.github.io"
DEFAULT_ENGINES="google,bing"
LOG_FILE=""
NOTIFY_WEBHOOK="${SEARCH_INDEXER_NOTIFY_WEBHOOK:-}"

readonly -a AVAILABLE_ENGINES=(
  "google:https://www.google.com/ping"
  "bing:https://www.bing.com/ping"
)

log() {
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" | tee -a "$LOG_FILE"
}

log_only() {
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*"
}

print_usage() {
  cat <<USAGE
Usage:
  $SCRIPT_NAME [options] [base_url] [sitemap_url]

Options:
  -h, --help                Tampilkan bantuan ini
  --dry-run                  Simulasi kirim, tidak melakukan request ke mesin pencari
  --timeout <sec>            Timeout koneksi/curl (default: ${DEFAULT_TIMEOUT})
  --log-file <path>          Lokasi file log (default: ${LOG_DIR}/search-indexer-<timestamp>.log)
  --engines <names>          Daftar mesin (comma-separated), default: ${DEFAULT_ENGINES}
                             Contoh: --engines google,bing
  --notify-webhook <url>     URL webhook notifikasi (Slack/Discord/Teams). Default dari env SEARCH_INDEXER_NOTIFY_WEBHOOK

Positional:
  base_url     Base URL website (default: ${DEFAULT_BASE_URL})
  sitemap_url  URL sitemap (default: <base_url>/sitemap.xml)

Contoh:
  $SCRIPT_NAME https://notedavidrinaldi.github.io
  $SCRIPT_NAME --dry-run --engines google,bing https://notedavidrinaldi.github.io https://notedavidrinaldi.github.io/sitemap.xml
  $SCRIPT_NAME --timeout 20 --log-file /tmp/indexer.log https://notedavidrinaldi.github.io
USAGE
}

trim() {
  sed 's/^[[:space:]]*//;s/[[:space:]]*$//' <<< "$1"
}

normalize_engine() {
  local name="$1"
  echo "$(echo "$name" | tr '[:upper:]' '[:lower:]' | sed 's/[[:space:]]//g')"
}

if [[ $# -eq 0 ]]; then
  BASE_URL="$DEFAULT_BASE_URL"
  SITEMAP_URL="${BASE_URL}/sitemap.xml"
  TIMEOUT="$DEFAULT_TIMEOUT"
  DRY_RUN=0
  SELECTED_ENGINES="$DEFAULT_ENGINES"
else
  BASE_URL=""
  SITEMAP_URL=""
  TIMEOUT="$DEFAULT_TIMEOUT"
  DRY_RUN=0
  SELECTED_ENGINES="$DEFAULT_ENGINES"

  while [[ $# -gt 0 ]]; do
    case "$1" in
      -h|--help)
        print_usage
        exit 0
        ;;
      --dry-run)
        DRY_RUN=1
        shift
        ;;
      --timeout)
        if [[ $# -lt 2 ]]; then
          echo "--timeout membutuhkan angka, contoh: --timeout 15" >&2
          exit 2
        fi
        TIMEOUT="$2"
        shift 2
        ;;
      --timeout=*)
        TIMEOUT="${1#*=}"
        shift
        ;;
      --log-file)
        if [[ $# -lt 2 ]]; then
          echo "--log-file membutuhkan path" >&2
          exit 2
        fi
        LOG_FILE="$(trim "$2")"
        shift 2
        ;;
      --log-file=*)
        LOG_FILE="$(trim "${1#*=}")"
        shift
        ;;
      --engines)
        if [[ $# -lt 2 ]]; then
          echo "--engines membutuhkan daftar, contoh: --engines google,bing" >&2
          exit 2
        fi
        SELECTED_ENGINES="$(normalize_engine "$2")"
        shift 2
        ;;
      --engines=*)
        SELECTED_ENGINES="$(normalize_engine "${1#*=}")"
        shift
        ;;
      --notify-webhook)
        if [[ $# -lt 2 ]]; then
          echo "--notify-webhook membutuhkan URL webhook" >&2
          exit 2
        fi
        NOTIFY_WEBHOOK="$(trim "$2")"
        shift 2
        ;;
      --notify-webhook=*)
        NOTIFY_WEBHOOK="$(trim "${1#*=}")"
        shift
        ;;
      --*)
        echo "Argumen tidak dikenal: $1" >&2
        print_usage
        exit 2
        ;;
      *)
        if [[ -z "$BASE_URL" ]]; then
          BASE_URL="$(trim "$1")"
        elif [[ -z "$SITEMAP_URL" ]]; then
          SITEMAP_URL="$(trim "$1")"
        else
          echo "Argumen terlalu banyak: $1" >&2
          print_usage
          exit 2
        fi
        shift
        ;;
    esac
  done

  if [[ -z "$BASE_URL" ]]; then
    BASE_URL="$DEFAULT_BASE_URL"
  fi
  if [[ -z "$SITEMAP_URL" ]]; then
    SITEMAP_URL="$BASE_URL/sitemap.xml"
  fi
fi

if [[ "$TIMEOUT" =~ ^[0-9]+$ ]] && (( TIMEOUT > 0 )); then
  :
else
  echo "Timeout tidak valid: $TIMEOUT" >&2
  exit 2
fi

if [[ "$SITEMAP_URL" != http://* && "$SITEMAP_URL" != https://* ]]; then
  echo "Sitemap harus URL yang valid (http/https): $SITEMAP_URL" >&2
  exit 2
fi

if [[ -z "$LOG_FILE" ]]; then
  mkdir -p "$LOG_DIR"
  LOG_FILE="$LOG_DIR/search-indexer-$(date +%Y%m%d-%H%M%S).log"
fi

IFS=',' read -r -a requested_engines <<< "$SELECTED_ENGINES"
selected_pairs=()
for req in "${requested_engines[@]}"; do
  req="$(normalize_engine "$req")"
  if [[ -z "$req" ]]; then
    continue
  fi

  found=0
  for pair in "${AVAILABLE_ENGINES[@]}"; do
    name="${pair%%:*}"
    if [[ "$name" == "$req" ]]; then
      selected_pairs+=("$pair")
      found=1
      break
    fi
  done

  if [[ $found -eq 0 ]]; then
    echo "Engine tidak dikenal: $req" >&2
    echo "Engine yang tersedia: google,bing" >&2
    exit 2
  fi
done

if [[ ${#selected_pairs[@]} -eq 0 ]]; then
  echo "Tidak ada engine yang dipilih." >&2
  exit 2
fi

# Validasi file sitemap sebelum submit
TMP_SITEMAP_BODY="$(mktemp -t search-indexer-sitemap-XXXXXX.xml)"
TMP_SITEMAP_ERR="$(mktemp -t search-indexer-sitemap-err-XXXXXX)"
cleanup() {
  rm -f "$TMP_SITEMAP_BODY" "$TMP_SITEMAP_ERR"
}
trap cleanup EXIT

notify_webhook() {
  local status_text="$1"
  local message="$2"
  if [[ -z "$NOTIFY_WEBHOOK" ]]; then
    return 0
  fi

  local escaped_message payload
  local full_message="[search-indexer] ${status_text}: ${message}"

  escaped_message="$(printf '%s' "$full_message" | sed \
    -e 's/\\/\\\\/g' \
    -e 's/"/\\\"/g')"

  if [[ "$NOTIFY_WEBHOOK" == *"discord.com/api/webhooks"* || "$NOTIFY_WEBHOOK" == *"discordapp.com/api/webhooks"* ]]; then
    payload="{\"content\":\"${escaped_message}\"}"
  elif [[ "$NOTIFY_WEBHOOK" == *"webhook.office.com"* || "$NOTIFY_WEBHOOK" == *"outlook.office.com/webhook"* || "$NOTIFY_WEBHOOK" == *"teams.microsoft.com"* ]]; then
    payload="{\"@type\":\"MessageCard\",\"@context\":\"https://schema.org/extensions\",\"summary\":\"search-indexer ${status_text}\",\"title\":\"search-indexer ${status_text}\",\"text\":\"${escaped_message}\"}"
  else
    payload="{\"text\":\"${escaped_message}\"}"
  fi

  curl -sS -m "$TIMEOUT" -X POST \
    -H 'Content-Type: application/json' \
    -d "$payload" \
    "$NOTIFY_WEBHOOK" >/dev/null 2>&1 || true
}

log "[Validator] Memvalidasi akses dan format sitemap: $SITEMAP_URL"
if ! curl -LsS -m "$TIMEOUT" --connect-timeout "$TIMEOUT" "$SITEMAP_URL" \
  -o "$TMP_SITEMAP_BODY" 2>"$TMP_SITEMAP_ERR"; then
  err_msg="$(cat "$TMP_SITEMAP_ERR" 2>/dev/null | tr '\n' ' ')"
  echo "Gagal mengambil sitemap: $err_msg" >&2
  exit 2
fi

if ! grep -Eq "<[[:space:]]*(urlset|sitemapindex)" "$TMP_SITEMAP_BODY"; then
  echo "Sitemap bukan XML sitemap yang valid (urlset/sitemapindex tidak ditemukan)." >&2
  exit 2
fi

# Siapkan log
: > "$LOG_FILE"

if [[ "$DRY_RUN" == "1" ]]; then
  log_only "[Mode] DRY-RUN: tidak ada request yang benar-benar dikirim."
  log "[Mode] DRY-RUN: tidak ada request yang benar-benar dikirim."
else
  log "[Mode] LIVE"
fi
log "[Config] Base URL: $BASE_URL"
log "[Config] Sitemap: $SITEMAP_URL"
log "[Config] Timeout: ${TIMEOUT}s"
log "[Config] Engines: ${selected_pairs[*]}"
log "[Config] Log detail: $LOG_FILE"

TOTAL_REQUESTS=0
SUCCESS_COUNT=0
FAIL_COUNT=0
UNKNOWN_COUNT=0

for pair in "${selected_pairs[@]}"; do
  engine_name="${pair%%:*}"
  endpoint="${pair#*:}"
  TOTAL_REQUESTS=$((TOTAL_REQUESTS + 1))

  log "=> ${engine_name}: ${endpoint}"

  if [[ "$DRY_RUN" == "1" ]]; then
    status="dry-run"
    log "   status=${status} (simulasi)"
    SUCCESS_COUNT=$((SUCCESS_COUNT + 1))
    continue
  fi

  tmp_body="$(mktemp -t search-indexer-${engine_name}-body-XXXXXX)"
  tmp_err="$(mktemp -t search-indexer-${engine_name}-err-XXXXXX)"
  body_target="$tmp_body"
  err_target="$tmp_err"

  if code=$(curl -GsS -m "$TIMEOUT" --connect-timeout "$TIMEOUT" \
    --data-urlencode "sitemap=$SITEMAP_URL" \
    -o "$body_target" -w "%{http_code}" "$endpoint" 2>"$err_target"); then
    status="$code"
    if [[ "$status" == "200" || "$status" == "201" || "$status" == "202" || "$status" == "301" || "$status" == "302" ]]; then
      log "   status=${status} -> OK"
      SUCCESS_COUNT=$((SUCCESS_COUNT + 1))
    else
      log "   status=${status} (response tidak lazim, cek: $body_target)"
      UNKNOWN_COUNT=$((UNKNOWN_COUNT + 1))
    fi
  else
    err_msg="$(cat "$err_target" 2>/dev/null | tr '\n' ' ')"
    log "   gagal: $err_msg"
    FAIL_COUNT=$((FAIL_COUNT + 1))
  fi

  rm -f "$tmp_body" "$tmp_err"

done

log "[Result] total=$TOTAL_REQUESTS sukses=$SUCCESS_COUNT unknown=$UNKNOWN_COUNT gagal=$FAIL_COUNT"
log "[Result] Jika sukses=total, script selesai sukses."
log "[Info] robots.txt: ${BASE_URL}/robots.txt"

RESULT_MESSAGE="[Result] total=${TOTAL_REQUESTS}, sukses=${SUCCESS_COUNT}, unknown=${UNKNOWN_COUNT}, gagal=${FAIL_COUNT}, dry_run=${DRY_RUN}, engines=${selected_pairs[*]}"

if [[ "$SUCCESS_COUNT" -eq "$TOTAL_REQUESTS" && "$FAIL_COUNT" -eq 0 && "$UNKNOWN_COUNT" -eq 0 ]]; then
  notify_webhook "OK" "$RESULT_MESSAGE"
  exit 0
fi
if [[ "$SUCCESS_COUNT" -gt 0 ]]; then
  notify_webhook "PARTIAL" "$RESULT_MESSAGE"
  exit 1
fi
notify_webhook "FAILED" "$RESULT_MESSAGE"
exit 2
