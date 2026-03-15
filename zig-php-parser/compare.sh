#!/usr/bin/env bash
# Compare PHP CLI vs AOT output for one or more scripts.
# Usage:
#   ./compare.sh <file_or_dir> [...]
# If no arguments are provided, the script scans fuzzy_scripts_extreme/*.php.

set -euo pipefail

ROOT_DIR=$(cd "$(dirname "$0")" && pwd)
INTERPRETER="$ROOT_DIR/zig-out/bin/php-interpreter"
DEFAULT_GLOB_DIR="$ROOT_DIR"
BUILD_DIR="$ROOT_DIR/.zigphp_aot_build"

PHP_TIMEOUT=${PHP_TIMEOUT:-15}
AOT_TIMEOUT=${AOT_TIMEOUT:-15}
COMPILE_TIMEOUT=${COMPILE_TIMEOUT:-60}

if [[ ! -x "$INTERPRETER" ]]; then
  echo "[ERROR] php-interpreter binary not found at $INTERPRETER" >&2
  exit 1
fi

TMP_DIR=$(mktemp -d -t compare-aot-XXXXXX)
cleanup() {
  rm -rf "$TMP_DIR"
}
trap cleanup EXIT

collect_files() {
  local target=$1
  if [[ -d $target ]]; then
    find "$target" -type f -name '*.php' | sort
  elif [[ -f $target ]]; then
    printf '%s\n' "$target"
  else
    echo "" >&2
  fi
}

# Build file list
declare -a FILES
if [[ $# -eq 0 ]]; then
  if compgen -G "$DEFAULT_GLOB_DIR/test_*.php" >/dev/null; then
    while IFS= read -r path; do
      FILES+=("$path")
    done < <(find "$DEFAULT_GLOB_DIR" -type f -name 'test_*.php' | sort)
  else
    echo "Usage: $0 <php-file-or-directory> [...]" >&2
    exit 1
  fi
else
  for arg in "$@"; do
    if [[ -d $arg || -f $arg ]]; then
      while IFS= read -r path; do
        [[ -n $path ]] && FILES+=("$path")
      done < <(collect_files "$arg")
    else
      echo "[WARN] Skipping unknown path: $arg" >&2
    fi
  done
fi

if [[ ${#FILES[@]} -eq 0 ]]; then
  echo "[ERROR] No PHP scripts found." >&2
  exit 1
fi

printf '[INFO] Testing %d script(s)\n' "${#FILES[@]}"

stat_pass=0
stat_mismatch=0
stat_compile_fail=0
stat_php_fail=0
stat_php_timeout=0
stat_aot_fail=0
stat_aot_timeout=0

for file in "${FILES[@]}"; do
  rel=${file#$ROOT_DIR/}
  bin="$TMP_DIR/$(basename "${file%.*}")_aot"
  compile_log="$TMP_DIR/compile.log"

  rm -f "$bin"
  rm -rf "$BUILD_DIR"

  printf '[RUN] %s\n' "$rel"

  if ! timeout "$COMPILE_TIMEOUT" "$INTERPRETER" --compile --output="$bin" "$file" >"$compile_log" 2>&1; then
    printf '  -> COMPILE_FAIL\n'
    cat "$compile_log"
    ((stat_compile_fail++))
    continue
  fi

  php_out="$TMP_DIR/php.out"
  aot_out="$TMP_DIR/aot.out"

  if ! timeout "$PHP_TIMEOUT" php "$file" >"$php_out" 2>"$TMP_DIR/php.err"; then
    printf '  -> PHP_FAIL (code=%d)\n' "$?"
    cat "$TMP_DIR/php.err"
    ((stat_php_fail++))
    continue
  fi

  if ! timeout "$AOT_TIMEOUT" "$bin" >"$aot_out" 2>"$TMP_DIR/aot.err"; then
    rc=$?
    if [[ $rc -eq 124 ]]; then
      printf '  -> AOT_TIMEOUT\n'
      ((stat_aot_timeout++))
    else
      printf '  -> AOT_FAIL (code=%d)\n' "$rc"
      cat "$TMP_DIR/aot.err"
      ((stat_aot_fail++))
    fi
    continue
  fi

  if cmp -s "$php_out" "$aot_out"; then
    printf '  -> PASS\n'
    ((stat_pass++))
  else
    printf '  -> MISMATCH\n'
    echo '--- PHP output ---'
    cat "$php_out"
    echo '--- AOT output ---'
    cat "$aot_out"
    ((stat_mismatch++))
  fi

done

printf '\n[SUMMARY]\n'
printf '  PASS:          %d\n' "$stat_pass"
printf '  MISMATCH:      %d\n' "$stat_mismatch"
printf '  COMPILE_FAIL:  %d\n' "$stat_compile_fail"
printf '  PHP_FAIL:      %d\n' "$stat_php_fail"
printf '  PHP_TIMEOUT:   %d\n' "$stat_php_timeout"
printf '  AOT_FAIL:      %d\n' "$stat_aot_fail"
printf '  AOT_TIMEOUT:   %d\n' "$stat_aot_timeout"
