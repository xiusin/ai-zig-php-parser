#!/usr/bin/env bash
# 永久侧门 E（任务 #117 顺带发现 → 新立工单 AOT-CODEGEN-010，2026-10-07）：
#   PHP 关键字**非全小写拼写**（Echo / ECHO / Print / If / RETURN / FUNCTION / CLASS / NEW / FOREACH …）
#   在 AOT 里的逐形结局
#
# 本门要回答的唯一问题：
#   同一语义只换关键字大小写 ⇒ AOT 与 PHP 真值的**结局类别**是否改变（静默空输出 / 致命 / 解析失败 / 仍等值）
#
# 机制锚点（实文核对，只读）：
#   `src/compiler/lexer.zig:384 lexIdentifier` 把**原始文本** `text` 直接交给
#   `keyword_lookup.lookupFast/lookup`（`:390-398`），而 `keyword_lookup.zig:6` 是
#   `std.StaticStringMap(Token.Tag).initComptime` ⇒ **大小写敏感**的完全哈希查找
#   ⇒ 任何非全小写拼写查不中 ⇒ 落到 `:401` 的 `t_string`（标识符）支 ⇒ 语义由后续 parser 随机决定
#
# 判读口径：
#   1) 等值 = 归一化合并 stdout+stderr 逐字节；exit 码只记录不判等
#   2) 单列三类计数器：
#      silent_empty = PHP 有输出而 AOT 输出**为空** ⇒ 最危险（rc=0 假绿面）
#      aot_fatal    = AOT 侧输出含 `Fatal error` / `Uncaught` / `error:`
#      compile_fail = AOT 编译期解析失败
#   3) 控制臂：每一组都配同语义的**全小写形**（`*_ctl`），**必须始终 SAME**
#      ⇒ 若某组小写形已红 ⇒ 该组的差异不可归因于大小写
#      固化坑（大写 ELSE）：必须用**真条件**形 ⇒ 实测 AOT 把 `ELSE {…}` 的块**无条件执行**，
#      若条件为假则 PHP 也只走 else 块 ⇒ 两侧输出偶然逐字节相同（零区分度）；真条件形才暴露多执行一行
#   4) 每形独立文件、独立编译；类名/函数名逐形专属（进程级全局注册表）
#   5) 产物名 aot_compile_*，且不落在源目录；KEEP_TEMP 不使用（本门只看运行结局，不看生成码）
#   6) 每形**只输出自身标记**（不加统一 `DONE` 行）⇒ `silent_empty` 判据 = AOT 输出为空文件而 PHP 侧非空
#      固化坑：`--compile` 遇 `Parse error` 时**退出码仍为 0 且不产出二进制** ⇒ 编译失败判据取「产物不可执行」
set -u
cd "$(dirname "$0")/../.." || exit 1
BIN="zig-out/bin/php-interpreter"
PHP="/opt/homebrew/bin/php"
OUT="fuzzy_scripts_720/tmp/c010_keyword_case_tmp.tsv"
T=$(mktemp -d /tmp/c010kw.XXXXXX)
trap 'rm -rf "$T"' EXIT
START=$(date +%s)

norm() { sed -E -e 's/[[:space:]]*$//' -e 's|/[^[:space:]:]*\.php:[0-9]+|FILE:LINE|g' -e 's| in [^ ]*\.php on line [0-9]+| in FILE:LINE|g' -e '/^Stack trace:/,$d' -e '/^$/d'; }

body_for() {
  case "$1" in
    # echo 组
    kw_echo_ctl)     printf '%s\n' 'echo "e=1", "\n";' ;;
    kw_echo_title)   printf '%s\n' 'Echo "e=1", "\n";' ;;
    kw_echo_upper)   printf '%s\n' 'ECHO "e=1", "\n";' ;;
    # print 组
    kw_print_ctl)    printf '%s\n' 'print "p=1\n";' ;;
    kw_print_title)  printf '%s\n' 'Print "p=1\n";' ;;
    # if/else 组
    kw_if_ctl)       printf '%s\n' '$x = 5;' 'if ($x > 0) { echo "i=gt\n"; } else { echo "i=le\n"; }' ;;
    kw_if_title)     printf '%s\n' '$x = 5;' 'If ($x > 0) { echo "i=gt\n"; } else { echo "i=le\n"; }' ;;
    kw_else_upper)   printf '%s\n' '$x = 5;' 'if ($x > 0) { echo "i=gt\n"; } ELSE { echo "i=le\n"; }' ;;
    # return 组
    kw_return_ctl)   printf '%s\n' 'function rc1($a) { return $a + 1; }' 'echo "r=", rc1(2), "\n";' ;;
    kw_return_upper) printf '%s\n' 'function rc2($a) { RETURN $a + 1; }' 'echo "r=", rc2(2), "\n";' ;;
    # function 组
    kw_function_ctl)   printf '%s\n' 'function fc3($a) { return $a * 2; }' 'echo "m=", fc3(3), "\n";' ;;
    kw_function_upper) printf '%s\n' 'FUNCTION fc4($a) { return $a * 2; }' 'echo "m=", fc4(3), "\n";' ;;
    # class/new 组
    kw_class_new_ctl)  printf '%s\n' 'class CC5 { public $w = 3; }' '$o = new CC5();' 'echo "c=", $o->w, "\n";' ;;
    kw_class_upper)    printf '%s\n' 'CLASS CC6 { public $w = 3; }' '$o = new CC6();' 'echo "c=", $o->w, "\n";' ;;
    kw_new_upper)      printf '%s\n' 'class CC7 { public $w = 3; }' '$o = NEW CC7();' 'echo "c=", $o->w, "\n";' ;;
    # foreach / while 组
    kw_foreach_ctl)  printf '%s\n' 'foreach ([1,2] as $v) { echo "f=", $v, "\n"; }' ;;
    kw_foreach_upper) printf '%s\n' 'FOREACH ([1,2] as $v) { echo "f=", $v, "\n"; }' ;;
    kw_while_upper)  printf '%s\n' '$i = 0;' 'WHILE ($i < 2) { echo "w=", $i, "\n"; $i = $i + 1; }' ;;
    # 已知可容大小写的形（布尔/NULL）
    kw_bool_upper)   printf '%s\n' '$t = TRUE; $f = FALSE; $n = NULL;' 'echo "b=", var_export($t, true), var_export($f, true), var_export($n, true), "\n";' ;;
    *) printf '' ;;
  esac
}

{ echo "# compiler_md5=$(md5 -q "$BIN")"
  echo "# lexer_md5=$(md5 -q src/compiler/lexer.zig)"
  echo "# keyword_lookup_md5=$(md5 -q src/compiler/keyword_lookup.zig)"
  echo "# columns: shape|php_rc|aot_rc|verdict|php_norm||aot_norm"
} > "$OUT"

COUNT=0; SAME_N=0; DIFF_N=0; CF_N=0; EMPTY_N=0; FATAL_N=0
for s in kw_echo_ctl kw_echo_title kw_echo_upper kw_print_ctl kw_print_title \
         kw_if_ctl kw_if_title kw_else_upper kw_return_ctl kw_return_upper \
         kw_function_ctl kw_function_upper kw_class_new_ctl kw_class_upper kw_new_upper \
         kw_foreach_ctl kw_foreach_upper kw_while_upper kw_bool_upper; do
  COUNT=$((COUNT + 1))
  SRC="$T/c010_${s}_tmp.php"
  printf '<?php\n' > "$SRC"
  body_for "$s" >> "$SRC"

  timeout 120 "$BIN" --compile --output="$T/aot_compile_c010_${s}_tmp" "$SRC" >"$T/$s.compile.log" 2>&1
  # 固化坑：`--compile` 遇 Parse error 时**退出码仍为 0** 且不产出二进制 ⇒ 判据取「产物不可执行」
  if [ ! -x "$T/aot_compile_c010_${s}_tmp" ]; then
    echo "$s|php_rc=NA|aot_rc=NA|COMPILE_FAIL|$(tail -2 "$T/$s.compile.log" | tr '\n|' '||')||" >> "$OUT"
    CF_N=$((CF_N + 1))
    continue
  fi

  timeout 10 "$PHP" "$SRC" >"$T/$s.php.out" 2>&1; prc=$?
  timeout 10 "$T/aot_compile_c010_${s}_tmp" >"$T/$s.aot.out" 2>&1; arc=$?
  php_n=$(norm < "$T/$s.php.out" | tr '\n' '|')
  aot_n=$(norm < "$T/$s.aot.out" | tr '\n' '|')
  if [ "$php_n" = "$aot_n" ]; then v=SAME; SAME_N=$((SAME_N + 1)); else v=DIFF; DIFF_N=$((DIFF_N + 1)); fi
  if [ ! -s "$T/$s.aot.out" ] && [ -s "$T/$s.php.out" ]; then EMPTY_N=$((EMPTY_N + 1)); fi
  if grep -qE 'Fatal error|Uncaught|^error:' "$T/$s.aot.out"; then FATAL_N=$((FATAL_N + 1)); fi
  echo "$s|php_rc=$prc|aot_rc=$arc|$v|$php_n||aot=$aot_n" >> "$OUT"
done

echo "ELAPSED=$(($(date +%s) - START))s" >> "$OUT"
echo "C010KW_DONE shapes=$COUNT same=$SAME_N diff=$DIFF_N silent_empty=$EMPTY_N aot_fatal=$FATAL_N compile_fail=$CF_N" >> "$OUT"
cat "$OUT"
