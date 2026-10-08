#!/usr/bin/env bash
# 永久侧门 I（任务 #120 → 工单 AOT-CODEGEN-010 §2.2 / §7-4「跨模式是否一并修」的量化前置，2026-10-07）：
#   同一批「混合大小写关键字」源形，在 **AOT / 解释器(tree) / 字节码(bytecode)** 三种执行模式下的
#   逐形结局对照 —— 老铁要裁决的是「是否只修 AOT」，而 §2.2 现有证据只有 4 形、且为定性描述。
#
# 源形取自**永久侧门 E 的同一批 19 形**（body 逐字复制，不修改侧门 E 本身 ⇒ 规则 11 未被违反），
# 使三模式与门 E 的 AOT 读数可直接横向对齐。
#
# 实测前先记录的机制差异（只读实文 + 本门首跑校正）：
#   `--mode` 选项：`tree`（默认）/ `bytecode` / `fast` / `auto`（`php-interpreter --help` 实文）
#   ⇒ **同一形在不同模式下结局类别可以完全不同**：
#      `Echo "e=1"` 实测 AOT = 空输出 rc=0；tree = `Undefined variable: $Echo`；bytecode = 空输出
#      ⇒ 「 lexer 是共享的」只保证**坍成 t_string** 这一步共享，**下游语义面不共享**
#
# 判读口径：
#   1) 等值 = 归一化合并 stdout+stderr 逐字节；exit 码只记录不判等
#   2) **本门口径新增**：VM 模式在 stderr 末尾打印 `=== PHP Interpreter Performance Statistics ===`
#      统计段（实测确认，非推测）⇒ norm() 必须从该行起整段删除，否则**所有** VM 臂恒 DIFF、门失去判别力；
#      该口径只用于本门，**不回改侧门 E/F/G**
#   3) AOT 侧 `--compile` 遇 Parse error 仍 rc=0 且无产物（规则 21）⇒ AOT 编译失败判据取「产物不可执行」
#   4) 计数器分三模式各一组，另给交叉面：
#      both_red     = 三模式全红 ⇒ 「一并修」才有共同收益
#      vm_only_red  = AOT 绿而任一 VM 模式红 ⇒ 只修 AOT 会**漏**的面
#      aot_only_red = AOT 红而两 VM 模式绿 ⇒ 只修 AOT 即够的面
#   5) 每形独立文件、独立编译；类名/函数名逐形专属；产物名 aot_compile_*；全命令带 timeout
#   6) 编译在**仓库根**执行；本门**只测不修**，零 `src/` 改动
#   7) **固化坑（首跑踩到）**：`ONLY=` 冒烟通道首版只改了 OUT 路径**未过滤循环** ⇒ 「冒烟」实际跑了全 19 形
#      并把全量读数写进 `*_smoke_tmp.tsv` ⇒ 形如「smoke 文件里的总数」不可当作冒烟结果引用。
#      现已补循环级过滤；注册读数一律取自无 `ONLY` 的全量跑，smoke 文件只作跨 run 自证用后删除
set -u
cd "$(dirname "$0")/../.." || exit 1
BIN="zig-out/bin/php-interpreter"
PHP="/opt/homebrew/bin/php"
OUT="fuzzy_scripts_720/tmp/c010_crossmode_tmp.tsv"
if [ -n "${ONLY:-}" ]; then OUT="fuzzy_scripts_720/tmp/c010_crossmode_smoke_tmp.tsv"; fi
T=$(mktemp -d /tmp/c010i.XXXXXX)
trap 'rm -rf "$T"' EXIT
START=$(date +%s)

norm() {
  sed -E -e 's/[[:space:]]*$//' \
         -e 's|/[^[:space:]:]*\.php:[0-9]+|FILE:LINE|g' \
         -e 's| in [^ ]*\.php on line [0-9]+| in FILE:LINE|g' \
         -e '/^Stack trace:/,$d' \
         -e '/^=== PHP Interpreter Performance Statistics ===$/,$d' \
         -e '/^$/d'
}

body_for() {
  case "$1" in
    kw_echo_ctl)     printf '%s\n' 'echo "e=1", "\n";' ;;
    kw_echo_title)   printf '%s\n' 'Echo "e=1", "\n";' ;;
    kw_echo_upper)   printf '%s\n' 'ECHO "e=1", "\n";' ;;
    kw_print_ctl)    printf '%s\n' 'print "p=1\n";' ;;
    kw_print_title)  printf '%s\n' 'Print "p=1\n";' ;;
    kw_if_ctl)       printf '%s\n' '$x = 5;' 'if ($x > 0) { echo "i=gt\n"; } else { echo "i=le\n"; }' ;;
    kw_if_title)     printf '%s\n' '$x = 5;' 'If ($x > 0) { echo "i=gt\n"; } else { echo "i=le\n"; }' ;;
    kw_else_upper)   printf '%s\n' '$x = 5;' 'if ($x > 0) { echo "i=gt\n"; } ELSE { echo "i=le\n"; }' ;;
    kw_return_ctl)   printf '%s\n' 'function rc1($a) { return $a + 1; }' 'echo "r=", rc1(2), "\n";' ;;
    kw_return_upper) printf '%s\n' 'function rc2($a) { RETURN $a + 1; }' 'echo "r=", rc2(2), "\n";' ;;
    kw_function_ctl)   printf '%s\n' 'function fc3($a) { return $a * 2; }' 'echo "m=", fc3(3), "\n";' ;;
    kw_function_upper) printf '%s\n' 'FUNCTION fc4($a) { return $a * 2; }' 'echo "m=", fc4(3), "\n";' ;;
    kw_class_new_ctl)  printf '%s\n' 'class CC5 { public $w = 3; }' '$o = new CC5();' 'echo "c=", $o->w, "\n";' ;;
    kw_class_upper)    printf '%s\n' 'CLASS CC6 { public $w = 3; }' '$o = new CC6();' 'echo "c=", $o->w, "\n";' ;;
    kw_new_upper)      printf '%s\n' 'class CC7 { public $w = 3; }' '$o = NEW CC7();' 'echo "c=", $o->w, "\n";' ;;
    kw_foreach_ctl)  printf '%s\n' 'foreach ([1,2] as $v) { echo "f=", $v, "\n"; }' ;;
    kw_foreach_upper) printf '%s\n' 'FOREACH ([1,2] as $v) { echo "f=", $v, "\n"; }' ;;
    kw_while_upper)  printf '%s\n' '$i = 0;' 'WHILE ($i < 2) { echo "w=", $i, "\n"; $i = $i + 1; }' ;;
    kw_bool_upper)   printf '%s\n' '$t = TRUE; $f = FALSE; $n = NULL;' 'echo "b=", var_export($t, true), var_export($f, true), var_export($n, true), "\n";' ;;
    *) printf '' ;;
  esac
}

{ echo "# compiler_md5=$(md5 -q "$BIN")"
  echo "# lexer_md5=$(md5 -q src/compiler/lexer.zig)"
  echo "# keyword_lookup_md5=$(md5 -q src/compiler/keyword_lookup.zig)"
  echo "# columns: shape|kind|verdict|php_norm||mode_norm|raw_rc"
} > "$OUT"

CNT=0
AOT_SAME=0; AOT_DIFF=0; AOT_CF=0
TREE_SAME=0; TREE_DIFF=0
BC_SAME=0; BC_DIFF=0
BOTH_RED=0; VM_ONLY_RED=0; AOT_ONLY_RED=0

red_of() { [ "$1" = DIFF ] || [ "$1" = COMPILE_FAIL ]; }

for s in kw_echo_ctl kw_echo_title kw_echo_upper kw_print_ctl kw_print_title \
         kw_if_ctl kw_if_title kw_else_upper kw_return_ctl kw_return_upper \
         kw_function_ctl kw_function_upper kw_class_new_ctl kw_class_upper kw_new_upper \
         kw_foreach_ctl kw_foreach_upper kw_while_upper kw_bool_upper; do
  if [ -n "${ONLY:-}" ]; then
    case ",$ONLY," in
      *",$s,"*) ;;
      *) continue ;;
    esac
  fi
  CNT=$((CNT + 1))
  SRC="$T/c010i_${s}_tmp.php"
  printf '<?php\n' > "$SRC"
  body_for "$s" >> "$SRC"

  timeout 10 "$PHP" "$SRC" >"$T/$s.php.out" 2>&1
  php_n=$(norm < "$T/$s.php.out" | tr '\n' '|')

  # --- VM tree ---
  timeout 10 "$BIN" --mode=tree "$SRC" >"$T/$s.tree.out" 2>&1; trc=$?
  tree_n=$(norm < "$T/$s.tree.out" | tr '\n' '|')
  if [ "$tree_n" = "$php_n" ]; then tv=SAME; TREE_SAME=$((TREE_SAME + 1)); else tv=DIFF; TREE_DIFF=$((TREE_DIFF + 1)); fi
  # --- VM bytecode ---
  timeout 10 "$BIN" --mode=bytecode "$SRC" >"$T/$s.bc.out" 2>&1; brc=$?
  bc_n=$(norm < "$T/$s.bc.out" | tr '\n' '|')
  if [ "$bc_n" = "$php_n" ]; then bv=SAME; BC_SAME=$((BC_SAME + 1)); else bv=DIFF; BC_DIFF=$((BC_DIFF + 1)); fi
  # --- AOT ---
  timeout 120 "$BIN" --compile --output="$T/aot_compile_c010i_${s}_tmp" "$SRC" >"$T/$s.clog" 2>&1
  if [ ! -x "$T/aot_compile_c010i_${s}_tmp" ]; then
    av=COMPILE_FAIL; aot_n=$(tail -2 "$T/$s.clog" | tr '\n|' '||'); AOT_CF=$((AOT_CF + 1))
  else
    timeout 10 "$T/aot_compile_c010i_${s}_tmp" >"$T/$s.aot.out" 2>&1; arc=$?
    aot_n=$(norm < "$T/$s.aot.out" | tr '\n' '|')
    if [ "$aot_n" = "$php_n" ]; then av=SAME; AOT_SAME=$((AOT_SAME + 1)); else av=DIFF; AOT_DIFF=$((AOT_DIFF + 1)); fi
  fi
  # 交叉面
  aot_red=0; vm_red=0
  red_of "$av" && aot_red=1
  { red_of "$tv" || red_of "$bv"; } && vm_red=1
  if [ "$aot_red" = 1 ] && [ "$vm_red" = 1 ]; then BOTH_RED=$((BOTH_RED + 1)); X=both_red
  elif [ "$aot_red" = 0 ] && [ "$vm_red" = 1 ]; then VM_ONLY_RED=$((VM_ONLY_RED + 1)); X=vm_only_red
  elif [ "$aot_red" = 1 ] && [ "$vm_red" = 0 ]; then AOT_ONLY_RED=$((AOT_ONLY_RED + 1)); X=aot_only_red
  else X=all_green; fi

  echo "$s|php|$php_n||tree=$tv($tree_n)|bc=$bv($bc_n)|aot=$av($aot_n)|$X" >> "$OUT"
done

RESID=$(ls -d .zigphp_aot_build_* 2>/dev/null | wc -l | tr -d ' ')
echo "ELAPSED=$(($(date +%s) - START))s" >> "$OUT"
echo "C010I_DONE shapes=$CNT tree_same=$TREE_SAME tree_diff=$TREE_DIFF bc_same=$BC_SAME bc_diff=$BC_DIFF aot_same=$AOT_SAME aot_diff=$AOT_DIFF aot_compile_fail=$AOT_CF both_red=$BOTH_RED vm_only_red=$VM_ONLY_RED aot_only_red=$AOT_ONLY_RED repo_build_residue=$RESID SMOKE_ONLY=$([ -n "${ONLY:-}" ] && echo 1 || echo 0)" >> "$OUT"
cat "$OUT"
