#!/bin/bash
# f12 determinism sweep: compile each pass/*.php twice with KEEP_TEMP, compare main.zig md5
cd /Users/wangjianjun/products/parser || exit 1
PASS_DIR="fuzzy_scripts_720/pass"
BIN="zig-out/bin/php-interpreter"
total=0
mismatch=0
notemp=0
for f in "$PASS_DIR"/*.php; do
  name=$(basename "$f")
  base="${name%.php}"
  total=$((total+1))
  ZIGPHP_AOT_KEEP_TEMP=1 timeout 120 "$BIN" --compile --no-debug-info "$f" 2>/tmp/f12_sw1.err >/dev/null
  d1=$(awk '/preserved/ {print $NF; exit}' /tmp/f12_sw1.err)
  ZIGPHP_AOT_KEEP_TEMP=1 timeout 120 "$BIN" --compile --no-debug-info "$f" 2>/tmp/f12_sw2.err >/dev/null
  d2=$(awk '/preserved/ {print $NF; exit}' /tmp/f12_sw2.err)
  if [ -z "$d1" ] || [ -z "$d2" ] || [ ! -f "$d1/main.zig" ] || [ ! -f "$d2/main.zig" ]; then
    notemp=$((notemp+1))
    echo "NOTEMP|$name"
  else
    m1=$(md5 -q "$d1/main.zig")
    m2=$(md5 -q "$d2/main.zig")
    if [ "$m1" != "$m2" ]; then
      mismatch=$((mismatch+1))
      echo "MISMATCH|$name|$m1|$m2"
    fi
  fi
  if [ -n "$d1" ]; then rm -rf "$d1"; fi
  if [ -n "$d2" ]; then rm -rf "$d2"; fi
  rm -f "$PASS_DIR/aot_compile_${base}"
done
echo "SWEEP_DONE total=$total mismatch=$mismatch notemp=$notemp"
