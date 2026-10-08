#!/bin/bash
# C008 臂尾 latch 门（永久门脚本）：无 else 的 if/elseif 链 + 臂尾 echo ⇒ 链后语句零发射
#
# 口径与坑（实测得出，勿改）：
#   1) 编译命令必须与官方回归一致：`--compile --output=<产物>`，默认档（不带 --optimize），
#      产物名 `aot_compile_<源名>`（宪法 §三-8，防误删源文件）。
#   2) 真值 = 系统 PHP（/opt/homebrew/bin/php），逐字节比较前先 norm()：
#      去掉行尾空白、把 `in <file>:<line>` 类栈信息归一（宪法 §七-5）。
#   3) 红形的 AOT 侧 rc 仍为 0（静默截断），因此判据只能取「归一化 stdout」，禁止拿 rc 当判据。
#   4) 每形独立编译（本门 7 次编译），不可共用一个产物：这些探针靠 $argv 选路，
#      而「靠 $argv 选路的驱动链」自身也吃本缺陷，会把驱动臂一起吞掉。
#   5) C 形为控制臂，必须与红形同批跑：本门只承认「红形 DIFF ∧ 控制臂全 SAME」。
set -uo pipefail

ROOT="/Users/wangjianjun/products/parser"
TMP="$ROOT/fuzzy_scripts_720/tmp"
INTERPRETER="$ROOT/zig-out/bin/php-interpreter"
PHP="/opt/homebrew/bin/php"
T="/tmp/c008_gate_$$"
mkdir -p "$T"
START=$(date +%s)

norm() {
    sed -E -e 's/[[:space:]]*$//' -e 's|/[^ ]*\.php:[0-9]+|FILE:LINE|g' \
           -e 's| in [^ ]*\.php on line [0-9]+| in FILE:LINE|g' \
           -e '/^Stack trace:/,$d' -e '/^$/d'
}

OUT_TSV="$TMP/c008_chain_tail_gate_tmp.tsv"
: > "$OUT_TSV"
same=0; diff=0; cfail=0

run_probe() {
    local name="$1"; shift
    local src="$TMP/${name}_tmp.php"
    local bin="$T/aot_compile_${name}_tmp"
    if ! timeout 120 "$INTERPRETER" --compile --output="$bin" "$src" >"$T/$name.compile.log" 2>&1; then
        echo "COMPILE_FAIL|$name|$(head -1 "$T/$name.compile.log")" >> "$OUT_TSV"
        cfail=$((cfail+1)); echo "  $name COMPILE_FAIL"; return
    fi
    local args_list="$*"
    local idx=0
    for arg in $args_list; do
        idx=$((idx+1))
        local a p rc_a
        a=$(timeout 10 "$bin" "$arg" 2>&1); rc_a=$?
        p=$(timeout 10 "$PHP" "$src" "$arg" 2>&1)
        a=$(printf '%s' "$a" | norm); p=$(printf '%s' "$p" | norm)
        if [ "$a" == "$p" ]; then
            same=$((same+1)); echo "SAME|$name#$idx|arg=$arg|rc_a=$rc_a" >> "$OUT_TSV"
            echo "  $name#$idx arg=$arg SAME"
        else
            diff=$((diff+1)); echo "DIFF|$name#$idx|arg=$arg|rc_a=$rc_a|aot=$(printf '%s' "$a" | tr '\n' '/')|php=$(printf '%s' "$p" | tr '\n' '/')" >> "$OUT_TSV"
            echo "  $name#$idx arg=$arg DIFF  aot=[$(printf '%s' "$a" | tr '\n' '/')] php=[$(printf '%s' "$p" | tr '\n' '/')]"
        fi
    done
}

# 无参控制臂以 '-' 占位（run_probe 内不传参给两侧，靠下面 special 处理）
run_probe_noarg() {
    local name="$1"
    local src="$TMP/${name}_tmp.php"
    local bin="$T/aot_compile_${name}_tmp"
    if ! timeout 120 "$INTERPRETER" --compile --output="$bin" "$src" >"$T/$name.compile.log" 2>&1; then
        echo "COMPILE_FAIL|$name|$(head -1 "$T/$name.compile.log")" >> "$OUT_TSV"
        cfail=$((cfail+1)); echo "  $name COMPILE_FAIL"; return
    fi
    local a p rc_a
    a=$(timeout 10 "$bin" 2>&1); rc_a=$?
    p=$(timeout 10 "$PHP" "$src" 2>&1)
    a=$(printf '%s' "$a" | norm); p=$(printf '%s' "$p" | norm)
    if [ "$a" == "$p" ]; then
        same=$((same+1)); echo "SAME|$name#1|arg=-|rc_a=$rc_a" >> "$OUT_TSV"; echo "  $name SAME"
    else
        diff=$((diff+1)); echo "DIFF|$name#1|arg=-|rc_a=$rc_a|aot=$(printf '%s' "$a" | tr '\n' '/')|php=$(printf '%s' "$p" | tr '\n' '/')" >> "$OUT_TSV"
        echo "  $name DIFF  aot=[$(printf '%s' "$a" | tr '\n' '/')] php=[$(printf '%s' "$p" | tr '\n' '/')]"
    fi
}

echo "compiler_md5=$(md5 -q "$INTERPRETER")" | tee "$T/stamps.txt"

run_probe c008_p1_top_echo_arm a b z
run_probe c008_p2_fn_echo_arm_return a b z
run_probe c008_p3_fn_echo_arm_assign a b z
run_probe c008_c1_if_else_arm a b z
run_probe c008_p4_loop_echo_arm a b z
run_probe_noarg c008_c2_arr_arm
run_probe_noarg c008_c3_echo_not_last
run_probe_noarg c008_c4_void_call_arm_tail

END=$(date +%s)
echo "C008_DONE same=$same diff=$diff compile_fail=$cfail elapsed=$((END-START))s"
cat "$OUT_TSV"
