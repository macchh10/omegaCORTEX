#!/usr/bin/env bash
#
# Weekly allowlisted log maintenance. Dry-run unless --apply is supplied.
#
set -euo pipefail

MODE="dry-run"
case "${1:-}" in
  "") ;;
  --apply) MODE="apply" ;;
  *) echo "Usage: $0 [--apply]" >&2; exit 2 ;;
esac

LOG_DIR="${HOME}/Library/Logs"
MAINTENANCE_LOG="${LOG_DIR}/omegacortex-maintenance.log"
KEEP_LINES=500
STANDARD_LIMIT_MB=20
LARGE_LIMIT_MB=50

mkdir -p "$LOG_DIR"

{
echo "=== weekly maintenance $(date '+%Y-%m-%d %H:%M:%S %Z') (${MODE}) ==="
echo "Disk before:"
df -h /

trim_log() {
  local file="$1"
  local limit_mb="$2"
  local size_bytes limit_bytes size_mb tmp

  [[ -f "$file" ]] || return 0
  size_bytes="$(stat -f '%z' "$file")"
  limit_bytes=$((limit_mb * 1024 * 1024))
  size_mb=$((size_bytes / 1024 / 1024))
  if (( size_bytes <= limit_bytes )); then
    echo "KEEP  ${file} (${size_mb}MB; limit ${limit_mb}MB)"
    return 0
  fi

  if [[ "$MODE" == "dry-run" ]]; then
    echo "WOULD TRIM ${file} (${size_mb}MB) to last ${KEEP_LINES} lines"
    return 0
  fi

  tmp="$(mktemp "${TMPDIR:-/tmp}/omegacortex-maintenance.XXXXXX")"
  if tail -n "$KEEP_LINES" "$file" > "$tmp" && cat "$tmp" > "$file"; then
    echo "TRIMMED ${file} (${size_mb}MB) to last ${KEEP_LINES} lines"
  else
    rm -f "$tmp"
    echo "FAILED to trim ${file}" >&2
    return 1
  fi
  rm -f "$tmp"
}

scan_logs() {
  local root="$1"
  local limit_mb="$2"
  shift 2
  if [[ ! -d "$root" ]]; then
    echo "MISSING ${root}"
    return 0
  fi

  find "$root" -maxdepth 1 -type f "$@" -print0 |
  while IFS= read -r -d '' file; do
    trim_log "$file" "$limit_mb"
  done
}

# Core service allowlist. DOLI is deliberately explicit and mandatory.
scan_logs "${LOG_DIR}/doli" "$STANDARD_LIMIT_MB" -name '*.log'
scan_logs "$LOG_DIR" "$STANDARD_LIMIT_MB" \( -name 'omegacortex-*.log' -o -name 'sam-hunter.*.log' \)

# Claude/Codex logs have a higher threshold and remain confined to Library/Logs.
scan_logs "$LOG_DIR" "$LARGE_LIMIT_MB" \( -iname 'claude*.log' -o -iname 'codex*.log' \)
scan_logs "${LOG_DIR}/Claude" "$LARGE_LIMIT_MB" -name '*.log'
scan_logs "${LOG_DIR}/Codex" "$LARGE_LIMIT_MB" -name '*.log'

clean_crash_reports() {
  local root="$1"
  local file
  if [[ ! -d "$root" ]]; then
    echo "MISSING ${root}"
    return 0
  fi

  find "$root" -type f -mtime +14 -print0 |
  while IFS= read -r -d '' file; do
    if [[ "$MODE" == "apply" ]]; then
      rm -f -- "$file"
      echo "DELETED old crash report ${file}"
    else
      echo "WOULD DELETE old crash report ${file}"
    fi
  done
}

clean_crash_reports "${LOG_DIR}/DiagnosticReports"
clean_crash_reports "${LOG_DIR}/CrashReporter"

echo "Disk after:"
df -h /
echo "=== weekly maintenance complete (${MODE}) ==="
} 2>&1 | tee -a "$MAINTENANCE_LOG"
