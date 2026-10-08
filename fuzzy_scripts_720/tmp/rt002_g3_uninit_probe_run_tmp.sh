#!/usr/bin/env bash
# 永久侧门 B（任务 #115 → 工单 AOT-RUNTIME-002 §3 G3，2026-10-07）：G3 污染对「未初始化态」的第二重后果
#
# 为什么是第三张门（口径，勿删）：
#   主门 rt002_isolation_gate_tmp.sh（total=12）与侧门 A rt002_g3_probe_run_tmp.sh（total=5）的
#   shapes= 读数都已写进工单 §6/§7 ⇒ 按流程教训「已引用 total= 的门禁止回头加形」，本门单独成文件、单独成 token。
#
# 本门要回答的唯一问题：
#   强转失败把异常对象写进槽时，若该 typed 属性**尚未初始化**，PHP 的「未初始化态」是否也被摧毁
#   （即读它不再报 `must not be accessed before initialization`，而是拿到异常对象）？
#   控制臂 `g3_uninit_clean`（无任何前置失败写）用来证明：AOT 本身的 before-initialization 语义是对的，
#   所以第二重后果**只由 G3 的多余写入造成**，修复不需要另动未初始化态。
#
# 固化坑：
#   1) 每形独立编译，纯直线语句，无 if/elseif 链（受 AOT-CODEGEN-008 零发射面污染的形状不进本门）
#   2) 等值判据 = 归一化后 stdout+stderr 合并逐字节；exit 码只记录不判等
#   3) 额外单列 before_init_seen：两侧输出里是否出现「must not be accessed before initialization」
#   4) 产物名 aot_compile_*，且不落在源目录
set -u
cd "$(dirname "$0")/../.." || exit 1
BIN="zig-out/bin/php-interpreter"
PHP="/opt/homebrew/bin/php"
OUT="fuzzy_scripts_720/tmp/rt002_g3_uninit_tmp.tsv"
T=$(mktemp -d /tmp/rt002g3u.XXXXXX)
trap 'rm -rf "$T"' EXIT
START=$(date +%s)

norm() { sed -E -e 's/[[:space:]]*$//' -e 's|/[^[:space:]:]*\.php:[0-9]+|FILE:LINE|g' -e 's| in [^ ]*\.php on line [0-9]+| in FILE:LINE|g' -e '/^Stack trace:/,$d' -e '/^$/d'; }

cat > "$T/prelude.php" <<'PRELUDE'
<?php
class UHolder {
    public int $n;
    public string $s = 'default';
}

$show = static function (callable $f): void {
    try {
        $f();
        echo "NO_ERROR\n";
    } catch (Throwable $e) {
        echo get_class($e) . ": " . $e->getMessage() . "\n";
    }
};
$c = new UHolder();
PRELUDE

body_for() {
  case "$1" in
    g3_uninit_polluted) printf '%s\n' \
      '$k = "n";' \
      '$show(static function () use ($c, $k): void { $c->$k = "str"; });' \
      '$show(static function () use ($c): void { echo "read=" . var_export($c->n, true) . "\n"; });' \
      '$show(static function () use ($c): void { $c->n = 5; });' \
      '$show(static function () use ($c): void { echo "after_ok=" . var_export($c->n, true) . "\n"; });' ;;
    g3_uninit_clean) printf '%s\n' \
      '$show(static function () use ($c): void { echo "read=" . var_export($c->n, true) . "\n"; });' \
      '$show(static function () use ($c): void { echo "isset=" . (isset($c->n) ? "1" : "0") . " propset=" . (property_exists($c, "n") ? "1" : "0") . "\n"; });' \
      '$show(static function () use ($c): void { $c->n = 7; });' \
      '$show(static function () use ($c): void { echo "after_ok=" . var_export($c->n, true) . "\n"; });' ;;
    *) printf '' ;;
  esac
}

{ echo "# compiler_md5=$(md5 -q "$BIN")"
  echo "# runtime_lib_template_md5=$(md5 -q src/aot/runtime_lib_template.zig)"
  echo "# ir_generator_md5=$(md5 -q src/aot/ir_generator.zig)"
  echo "# prelude_md5=$(md5 -q "$T/prelude.php")"
  echo "# columns: shape|php_rc|aot_rc|verdict|before_init(php/aot)||php_norm||aot_norm"
} > "$OUT"

COUNT=0; SAME_N=0; DIFF_N=0; CF_N=0; LOST_N=0
for s in g3_uninit_polluted g3_uninit_clean; do
  COUNT=$((COUNT + 1))
  SRC="$T/g3u_${s}_tmp.php"
  cp "$T/prelude.php" "$SRC"
  body_for "$s" >> "$SRC"
  echo 'echo "DONE\n";' >> "$SRC"

  if ! timeout 120 "$BIN" --compile --output="$T/aot_compile_g3u_${s}_tmp" "$SRC" >"$T/$s.compile.log" 2>&1; then
    echo "$s|php_rc=NA|aot_rc=NA|COMPILE_FAIL|- $(tail -3 "$T/$s.compile.log" | tr '\n' '|')" >> "$OUT"
    CF_N=$((CF_N + 1))
    continue
  fi

  timeout 10 "$PHP" "$SRC" >"$T/$s.php.out" 2>&1; prc=$?
  timeout 10 "$T/aot_compile_g3u_${s}_tmp" >"$T/$s.aot.out" 2>&1; arc=$?
  php_n=$(norm < "$T/$s.php.out" | tr '\n' '|')
  aot_n=$(norm < "$T/$s.aot.out" | tr '\n' '|')
  if [ "$php_n" = "$aot_n" ]; then v=SAME; SAME_N=$((SAME_N + 1)); else v=DIFF; DIFF_N=$((DIFF_N + 1)); fi
  if grep -q 'must not be accessed before initialization' "$T/$s.php.out"; then pb=YES; else pb=NO; fi
  if grep -q 'must not be accessed before initialization' "$T/$s.aot.out"; then ab=YES; else ab=NO; fi
  if [ "$pb" = YES ] && [ "$ab" = NO ]; then LOST_N=$((LOST_N + 1)); fi
  echo "$s|php_rc=$prc|aot_rc=$arc|$v|before_init(php=$pb/aot=$ab)|$php_n||aot=$aot_n" >> "$OUT"
done

echo "ELAPSED=$(($(date +%s) - START))s" >> "$OUT"
echo "G3UNINIT_DONE shapes=$COUNT same=$SAME_N diff=$DIFF_N state_lost=$LOST_N compile_fail=$CF_N" >> "$OUT"
cat "$OUT"
