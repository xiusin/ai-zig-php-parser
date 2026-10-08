#!/usr/bin/env bash
# 永久门（任务 #114 → 工单 AOT-CODEGEN-009，2026-10-07）：::class 解析四面门
#   A = parent::class（有父类：应为父类名，实测 AOT 输出字面量 "parent"）
#   B = 无父类作用域的 parent::class（PHP Fatal rc=255；实测 AOT rc=0 且输出 "parent" ⇒ 静默错值 + 丢致命）
#   C = $对象变量::class（实测 AOT 输出空串，PHP 输出实例类名）
#   D = $字符串变量::class（PHP Fatal rc=255「Cannot use "::class" on string」；实测 AOT rc=0 且照常解析出类名 ⇒ 静默放行非法语法）
# 控制面（同门内必须保持 SAME，禁止顺手改）：self::class、static::class 三层继承 LSB、字面量 Class::class、get_class()
# 固化口径：
#   1) 每形独立文件独立编译（argv 派发链会吃掉自己的臂 ⇒ CODEGEN-008 §3B）
#   2) 探针全为直线语句，不含 if/elseif 链 ⇒ 本门 DIFF 只能归因 ::class 解析
#   3) 判据 = 归一化合并 stdout+stderr 逐字节；exit 码只记录（B 形两侧 255）
set -u
cd "$(dirname "$0")/../.." || exit 1
BIN="zig-out/bin/php-interpreter"
PHP="/opt/homebrew/bin/php"
P="fuzzy_scripts_720/tmp"
OUT="$P/c009_class_const_gate_tmp.tsv"
T=$(mktemp -d /tmp/c009_gate.XXXXXX)
trap 'rm -rf "$T"' EXIT
START=$(date +%s)

norm() { sed -E -e 's/[[:space:]]*$//' -e 's|/[^[:space:]:]*\.php:[0-9]+|FILE:LINE|g' -e 's| in [^ ]*\.php on line [0-9]+| in FILE:LINE|g' -e '/^Stack trace:/,$d' -e '/^$/d'; }

{ echo "# compiler_md5=$(md5 -q "$BIN")"
  echo "# native_linker_md5=$(md5 -q src/aot/native_linker.zig)"
  echo "# ir_generator_md5=$(md5 -q src/aot/ir_generator.zig)"
  echo "# runtime_lib_template_md5=$(md5 -q src/aot/runtime_lib_template.zig)"
  echo "# columns: probe|php_rc|aot_rc|verdict|php_norm||aot_norm"
} > "$OUT"

SAME_N=0; DIFF_N=0; CF_N=0; PROBE_N=0
for f in c009_a_parent_class_tmp c009_b_no_parent_tmp c009_c_var_class_tmp c009_d_str_class_tmp; do
  PROBE_N=$((PROBE_N + 1))
  SRC="$P/$f.php"
  if ! timeout 120 "$BIN" --compile --output="$T/aot_compile_$f" "$SRC" >"$T/$f.compile.log" 2>&1; then
    echo "$f|php_rc=NA|aot_rc=NA|COMPILE_FAIL|-||- $(tail -3 "$T/$f.compile.log" | tr '\n' '|')" >> "$OUT"
    CF_N=$((CF_N + 1))
    continue
  fi
  timeout 10 "$PHP" "$SRC" >"$T/$f.php.out" 2>&1; prc=$?
  timeout 10 "$T/aot_compile_$f" >"$T/$f.aot.out" 2>&1; arc=$?
  php_n=$(norm < "$T/$f.php.out" | tr '\n' '|')
  aot_n=$(norm < "$T/$f.aot.out" | tr '\n' '|')
  if [ "$php_n" = "$aot_n" ]; then v=SAME; SAME_N=$((SAME_N + 1)); else v=DIFF; DIFF_N=$((DIFF_N + 1)); fi
  echo "$f|php_rc=$prc|aot_rc=$arc|$v|$php_n||aot=$aot_n" >> "$OUT"
done

echo "ELAPSED=$(($(date +%s) - START))s" >> "$OUT"
echo "C009_DONE probes=$PROBE_N same=$SAME_N diff=$DIFF_N compile_fail=$CF_N" >> "$OUT"
cat "$OUT"
