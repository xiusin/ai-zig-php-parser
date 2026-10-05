#!/bin/bash
# spot-check driver v2: compile (per-file log + AOT-CANARY grep) + run AOT vs PHP ground truth
cd /Users/wangjianjun/products/parser
LOGDIR=/tmp/spot_logs
rm -rf "$LOGDIR"; mkdir -p "$LOGDIR"
PASS=0; FAIL=0; CANARY=0
for f in "$@"; do
  base=$(basename "$f" .php)
  rm -f "aot_compile_$base" "$(dirname "$f")/aot_compile_$base"
  timeout 120 zig-out/bin/php-interpreter --compile --no-debug-info "$f" > "$LOGDIR/$base.clog" 2>&1
  cexit=$?
  if grep -q "AOT-CANARY" "$LOGDIR/$base.clog"; then
    echo "$base CANARY_FIRE:"; grep "AOT-CANARY" "$LOGDIR/$base.clog"; CANARY=$((CANARY+1))
  fi
  bin="$(dirname "$f")/aot_compile_$base"
  if [ $cexit -ne 0 ] || [ ! -x "$bin" ]; then
    echo "$base COMPILE_FAIL exit=$cexit"; tail -3 "$LOGDIR/$base.clog"; FAIL=$((FAIL+1)); continue
  fi
  timeout 15 /opt/homebrew/bin/php "$f" 2>/dev/null | grep -v "Deprecated" | grep -v '^$' > "$LOGDIR/$base.php"
  pexit=${PIPESTATUS[0]}
  timeout 15 "$bin" 2>/dev/null | grep -v "Deprecated" | grep -v '^$' > "$LOGDIR/$base.aot"
  aexit=$?
  if [ $aexit -ne 0 ]; then
    echo "$base AOT_RUN_FAIL exit=$aexit (php=$pexit)"; FAIL=$((FAIL+1)); rm -f "$bin"; continue
  fi
  d=$(diff "$LOGDIR/$base.php" "$LOGDIR/$base.aot" | wc -l | tr -d ' ')
  if [ "$d" = "0" ]; then echo "$base MATCH"; PASS=$((PASS+1)); else echo "$base DIFF=$d"; sed -n '1,12p' <(diff "$LOGDIR/$base.php" "$LOGDIR/$base.aot"); FAIL=$((FAIL+1)); fi
  rm -f "$bin"
done
echo "SPOT RESULT: PASS=$PASS FAIL=$FAIL CANARY=$CANARY"
