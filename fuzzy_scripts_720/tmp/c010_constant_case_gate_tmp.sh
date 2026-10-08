#!/usr/bin/env bash
# 永久侧门 G（任务 #119 顺带发现 → 工单 AOT-CODEGEN-010 §5 路线 R-2b，2026-10-07）：
#   运行期**内置常量表按单拼写建键**这一张面孔的逐形结局
#   —— 与侧门 E/F 的「关键字大小写」缺陷**无关**：本门全部探针源码内**没有任何大写关键字拼写**，
#      走的是 `constant("<名字>")` 动态查名入口，故 R-2（只改 lexer）对本面**零收敛**。
#
# 机制锚点（实文核对，只读）：
#   `src/aot/runtime_lib_template.zig:7614 .{ .name = "TRUE", .value = true }`、`:7615 "FALSE"`、
#   `:7637 dupe(u8, "NULL")` ⇒ 表键**只有大写一种拼写**；
#   生成码 `getGlobalVar`（`main.zig:1043`）先查 `runtime.constants.get(name)`（`:1066-1070`）⇒
#   查名侧同样**大小写敏感** ⇒ 非大写拼写的内置常量名一律落空 ⇒ `Undefined constant`
#
# 本门要回答的唯一问题：
#   内置常量名换拼写 ⇒ 结局是否改变；以及**覆盖面边界在哪**（禁止把修复扩到本不该敏感的名字）
#
# 判读口径：
#   1) 等值 = 归一化合并 stdout+stderr 逐字节；exit 码只记录不判等
#   2) **本门自定口径（不回改侧门 E/F）**：norm() 额外做三件事，缺一则「两侧都 Fatal」的守卫臂失去判别力：
#      ① 剥离行首 `PHP ` 前缀（AOT 侧 fatal 文本不带该前缀）
#      ② 删除 `in <路径>.php:NN` / `in <路径>.php on line NN` 定位尾巴（按宪法 §七-5 AOT 行号本就无意义）
#      ③ 折叠 `Fatal error:` 后的双空格（PHP 侧为两个空格、AOT 侧一个）
#      ⇒ 守卫臂要求**语义逐字节等值**（红面判据不受此口径影响，因其差异在值而非文本格式）
#      **固化坑（首跑踩到）**：`PHP ` 前缀**不在行首** —— 每形先 `echo "e="` 自带标记，
#      实测行形如 `e=PHP Fatal error: …` ⇒ 锚定 `^PHP ` 的替换**静默不触发**，两枚守卫臂被误判 DIFF；
#      修正为不限位置改写 `PHP Fatal` → `Fatal`。本门只登记**修正后**的总数。
#   3) 两类计数器：
#      red_expected   = 三枚内置常量混合/小写拼写形 ⇒ 现状必为 **DIFF**（红面登记）
#      guard_same     = 三枚「本就该大小写敏感」形（非关键字内置常量 × 用户常量正写 × 用户常量错写）
#                       ⇒ 现状必为 **SAME**；**若某日这些形转红，说明修复扩面越界**
#   4) 每形独立文件、独立编译、纯直线语句；产物名 aot_compile_*，不落在源目录
#   5) 编译必须在**仓库根目录**执行（固化坑：`cd` 到 /tmp 后 `--compile` 报
#      `executable generation failed: FileNotFound` 且 rc≠0 无产物 ⇒ 会被误读成解析失败）
#   6) `--compile` 遇 Parse error 时**退出码仍为 0 且不产出二进制** ⇒ 编译失败判据取「产物不可执行」
#   7) 本门**只测不修**
set -u
cd "$(dirname "$0")/../.." || exit 1
BIN="zig-out/bin/php-interpreter"
PHP="/opt/homebrew/bin/php"
OUT="fuzzy_scripts_720/tmp/c010_constant_case_tmp.tsv"
T=$(mktemp -d /tmp/c010g.XXXXXX)
trap 'rm -rf "$T"' EXIT
START=$(date +%s)

norm() { sed -E -e 's/[[:space:]]*$//' -e 's|^PHP ||' -e 's|PHP Fatal|Fatal|g' -e 's| ?in [^ ]*\.php on line [0-9]+||g' -e 's| ?in [^ ]*\.php:[0-9]+||g' -e 's|  +| |g' -e '/^Stack trace:/,$d' -e '/^$/d'; }

body_for() {
  case "$1" in
    # 红面：三枚内置常量名换拼写（PHP 8.5.8 全部可解析，AOT 侧全 Fatal）
    k_const_true_lower)  printf '%s\n' 'echo "a=", var_export(constant("true"), true), "\n";' ;;
    k_const_false_lower) printf '%s\n' 'echo "b=", var_export(constant("false"), true), "\n";' ;;
    k_const_null_title)  printf '%s\n' 'echo "c=", var_export(constant("Null"), true), "\n";' ;;
    # 等值臂：内置常量大写拼写（现状唯一可用拼写）
    k_const_true_upper)  printf '%s\n' 'echo "d=", var_export(constant("TRUE"), true), "\n";' ;;
    # 守卫臂 1：非关键字内置常量的小写名 —— PHP 自身亦 Fatal ⇒ 修复禁止扩面
    k_const_nonkw_lower) printf '%s\n' 'echo "e=", var_export(constant("php_int_max"), true), "\n";' ;;
    # 守卫臂 2：用户常量正写 ⇒ 两侧同值
    k_const_user_exact)  printf '%s\n' 'define("GgC1", 7);' 'echo "f=", constant("GgC1"), "\n";' ;;
    # 守卫臂 3：用户常量错写 —— PHP 自身亦 Fatal ⇒ 修复禁止扩面
    k_const_user_wrong)  printf '%s\n' 'define("GgC2", 8);' 'echo "g=", var_export(constant("ggc2"), true), "\n";' ;;
    *) printf '' ;;
  esac
}

{ echo "# compiler_md5=$(md5 -q "$BIN")"
  echo "# runtime_lib_template_md5=$(md5 -q src/aot/runtime_lib_template.zig)"
  echo "# columns: shape|php_rc|aot_rc|verdict|role|php_norm||aot_norm"
} > "$OUT"

COUNT=0; SAME_N=0; DIFF_N=0; CF_N=0; RED_N=0; GUARD_OK=0; GUARD_BAD=0
for s in k_const_true_lower k_const_false_lower k_const_null_title k_const_true_upper \
         k_const_nonkw_lower k_const_user_exact k_const_user_wrong; do
  COUNT=$((COUNT + 1))
  case "$s" in
    k_const_true_lower|k_const_false_lower|k_const_null_title) ROLE=red_expected ;;
    *) ROLE=guard_same ;;
  esac
  SRC="$T/c010g_${s}_tmp.php"
  printf '<?php\n' > "$SRC"
  body_for "$s" >> "$SRC"

  timeout 120 "$BIN" --compile --output="$T/aot_compile_c010g_${s}_tmp" "$SRC" >"$T/$s.compile.log" 2>&1
  if [ ! -x "$T/aot_compile_c010g_${s}_tmp" ]; then
    echo "$s|php_rc=NA|aot_rc=NA|COMPILE_FAIL|$ROLE|$(tail -2 "$T/$s.compile.log" | tr '\n|' '||')||" >> "$OUT"
    CF_N=$((CF_N + 1))
    continue
  fi

  timeout 10 "$PHP" "$SRC" >"$T/$s.php.out" 2>&1; prc=$?
  timeout 10 "$T/aot_compile_c010g_${s}_tmp" >"$T/$s.aot.out" 2>&1; arc=$?
  php_n=$(norm < "$T/$s.php.out" | tr '\n' '|')
  aot_n=$(norm < "$T/$s.aot.out" | tr '\n' '|')
  if [ "$php_n" = "$aot_n" ]; then v=SAME; SAME_N=$((SAME_N + 1)); else v=DIFF; DIFF_N=$((DIFF_N + 1)); fi
  if [ "$ROLE" = "red_expected" ]; then
    [ "$v" = "DIFF" ] && RED_N=$((RED_N + 1))
  else
    if [ "$v" = "SAME" ]; then GUARD_OK=$((GUARD_OK + 1)); else GUARD_BAD=$((GUARD_BAD + 1)); fi
  fi
  echo "$s|php_rc=$prc|aot_rc=$arc|$v|$ROLE|$php_n||aot=$aot_n" >> "$OUT"
done

echo "ELAPSED=$(($(date +%s) - START))s" >> "$OUT"
echo "C010G_DONE shapes=$COUNT same=$SAME_N diff=$DIFF_N red_confirmed=$RED_N guard_same=$GUARD_OK guard_red=$GUARD_BAD compile_fail=$CF_N" >> "$OUT"
cat "$OUT"
