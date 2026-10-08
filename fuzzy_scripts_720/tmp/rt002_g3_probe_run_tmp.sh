#!/usr/bin/env bash
# 永久侧门（任务 #115 → 工单 AOT-RUNTIME-002 §3 G3，2026-10-07）：强转失败槽污染的「入口 × 类型分支」矩阵
#
# 为什么另起一张门（口径，勿删）：
#   主门 rt002_isolation_gate_tmp.sh 的 `RT002_DONE shapes=12` 读数已写进工单 §6 与变更文档，按流程教训
#   （门 total= 已被验收记录引用 ⇒ 禁止回头加形，另立独立门）本门的 5 形单独成文件、单独成 token。
#
# 本门要回答的唯一问题：
#   G3「异常对象被写进 typed 槽」是否只在 `php_object_set`（字面属性名，:19461/:19462）发生，
#   还是同样发生在 `php_object_set_dynamic`（可变属性名，:19335/:19336）；以及 `coercePropertyType`
#   的哪些失败分支（int / array / 类名 / null）都会交出被污染的返回值。
#
#   主门无此覆盖：val_dyn 走 readonly 支（在 coerce 之前 return），从未打到 :19335。
#
# 固化坑：
#   1) 每形独立编译，纯直线语句，无任何 if/elseif 链（链派发受 AOT-CODEGEN-008 零发射面污染）
#   2) 等值判据 = 归一化后 stdout+stderr 合并逐字节；exit 码只记录不判等
#   3) 产物名 aot_compile_*，且不落在源目录
set -u
cd "$(dirname "$0")/../.." || exit 1
BIN="zig-out/bin/php-interpreter"
PHP="/opt/homebrew/bin/php"
OUT="fuzzy_scripts_720/tmp/rt002_g3_probe_tmp.tsv"
T=$(mktemp -d /tmp/rt002g3.XXXXXX)
trap 'rm -rf "$T"' EXIT
START=$(date +%s)

norm() { sed -E -e 's/[[:space:]]*$//' -e 's|/[^[:space:]:]*\.php:[0-9]+|FILE:LINE|g' -e 's| in [^ ]*\.php on line [0-9]+| in FILE:LINE|g' -e '/^Stack trace:/,$d' -e '/^$/d'; }

cat > "$T/prelude.php" <<'PRELUDE'
<?php
class GBase {}
class GOther {}

class GHolder {
    public int $count = 0;
    public array $meta = [];
    public ?GBase $b = null;
}

$show = static function (callable $f): void {
    try {
        $f();
        echo "NO_ERROR\n";
    } catch (Throwable $e) {
        echo get_class($e) . ": " . $e->getMessage() . "\n";
    }
};
$c = new GHolder();
echo "obj=" . get_class($c) . " count=" . $c->count . "\n";
PRELUDE

body_for() {
  case "$1" in
    g3_set_int)   printf '%s\n' '$show(static function () use ($c): void { $c->count = "str"; });' 'echo "slot=" . var_export($c->count, true) . " type=" . gettype($c->count) . "\n";' ;;
    g3_dyn_int)   printf '%s\n' '$k = "count";' '$show(static function () use ($c, $k): void { $c->$k = "str"; });' 'echo "slot=" . var_export($c->count, true) . " type=" . gettype($c->count) . "\n";' ;;
    g3_dyn_array) printf '%s\n' '$k = "meta";' '$show(static function () use ($c, $k): void { $c->$k = 7; });' 'echo "slot=" . var_export($c->meta, true) . " type=" . gettype($c->meta) . "\n";' ;;
    g3_set_class) printf '%s\n' '$o = new GOther();' '$show(static function () use ($c, $o): void { $c->b = $o; });' 'echo "slot=" . var_export($c->b, true) . " type=" . gettype($c->b) . "\n";' ;;
    g3_dyn_null)  printf '%s\n' '$k = "count";' '$show(static function () use ($c, $k): void { $c->$k = null; });' 'echo "slot=" . var_export($c->count, true) . " type=" . gettype($c->count) . "\n";' ;;
    *)            printf '' ;;
  esac
}

{ echo "# compiler_md5=$(md5 -q "$BIN")"
  echo "# runtime_lib_template_md5=$(md5 -q src/aot/runtime_lib_template.zig)"
  echo "# ir_generator_md5=$(md5 -q src/aot/ir_generator.zig)"
  echo "# prelude_md5=$(md5 -q "$T/prelude.php")"
  echo "# columns: shape|php_rc|aot_rc|verdict|slot_face||php_norm||aot_norm"
} > "$OUT"

COUNT=0; SAME_N=0; DIFF_N=0; CF_N=0; POLL_N=0
for s in g3_set_int g3_dyn_int g3_dyn_array g3_set_class g3_dyn_null; do
  COUNT=$((COUNT + 1))
  SRC="$T/g3_${s}_tmp.php"
  cp "$T/prelude.php" "$SRC"
  body_for "$s" >> "$SRC"
  echo 'echo "DONE\n";' >> "$SRC"

  if ! timeout 120 "$BIN" --compile --output="$T/aot_compile_g3_${s}_tmp" "$SRC" >"$T/$s.compile.log" 2>&1; then
    echo "$s|php_rc=NA|aot_rc=NA|COMPILE_FAIL|- $(tail -3 "$T/$s.compile.log" | tr '\n' '|')" >> "$OUT"
    CF_N=$((CF_N + 1))
    continue
  fi

  timeout 10 "$PHP" "$SRC" >"$T/$s.php.out" 2>&1; prc=$?
  timeout 10 "$T/aot_compile_g3_${s}_tmp" >"$T/$s.aot.out" 2>&1; arc=$?
  php_n=$(norm < "$T/$s.php.out" | tr '\n' '|')
  aot_n=$(norm < "$T/$s.aot.out" | tr '\n' '|')
  if [ "$php_n" = "$aot_n" ]; then v=SAME; SAME_N=$((SAME_N + 1)); else v=DIFF; DIFF_N=$((DIFF_N + 1)); fi
  if grep -q "TypeError::__set_state" "$T/$s.aot.out"; then p=POLLUTED; POLL_N=$((POLL_N + 1)); else p=clean; fi
  echo "$s|php_rc=$prc|aot_rc=$arc|$v|slot_face=$p|$php_n||aot=$aot_n" >> "$OUT"
done

echo "ELAPSED=$(($(date +%s) - START))s" >> "$OUT"
echo "G3PROBE_DONE shapes=$COUNT same=$SAME_N diff=$DIFF_N polluted=$POLL_N compile_fail=$CF_N" >> "$OUT"
cat "$OUT"
