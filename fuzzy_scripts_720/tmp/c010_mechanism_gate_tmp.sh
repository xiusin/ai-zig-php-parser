#!/usr/bin/env bash
# 永久侧门 F（任务 #119 → 工单 AOT-CODEGEN-010 §3 R-1 归因轮，2026-10-07）：
#   大写关键字的「四类结局」各由**哪一行**造成 —— 用生成码发射面判别，不看运行输出定成因
#
# 本门要回答的唯一问题：
#   同一枚大写关键字，结局是「静默空输出」还是「致命」还是「解析失败」还是「偶然等值」，
#   取决于 **parser 把它接成了哪种节点** ⇒ 生成码里「有没有指令」就是唯一判据。
#
# 成因（首跑即定案，实文 + 生成码双证）：
#   共同上游 = `src/compiler/lexer.zig:384-402`（原文切片交 `keyword_lookup.zig:6` 大小写敏感表 ⇒
#              失配落 `:400-402` = `.t_string` 标识符）。此后分四支：
#   A 类（**静默空输出 rc=0**）`Echo "x";`
#     = `parser.zig:480-486` `.t_string`（peek 非 colon）→ `parseExpressionStatement()`
#     → `parser.zig:2410` **`if (self.curr.tag == .semicolon) self.nextToken();`（软分号：缺 `;` 不报错）**
#     → 剩余 token 被**重新切成独立语句**；裸标识符经 `parser.zig:3044-3061` 成 `.variable` 节点
#     ⇒ 发射面 = **零指令**（实测 `__main__` 体只剩 `return Value.initNull()`，且字符串字面量
#        **连 static_strings 表项都没有** ⇒ 整个语句在 parse/IR 层面消失，不是运行期 no-op）
#   B 类（**运行致命**）`Echo ("x");` / `WHILE (...)` / `FUNCTION fc4(){}`
#     = 同一支，但 `parser.zig:2789-2791` 的 postfix 循环看到 `l_paren` ⇒ 生成**函数调用**节点
#     ⇒ 发射面 = 有 call ⇒ 运行 `Call to undefined function <原样大写名>()`
#     ⇒ **A/B 两支同源码只差一对括号** ⇒ 本门 m_echo_bare_title（A）/ m_echo_paren_title（B）即该判别对；
#        控制臂 m_echo_bare_ctl 证明「静默」来自 A 支的零指令，而非运行期把 echo 吞掉
#   C 类（**解析失败**）`If (...){}else{}` / `FOREACH ([] as $v)`
#     = 大写头被接成 call 后，其后的 `else`/`as` 落到语句层 `parser.zig:496 else =>` 支 ⇒
#       `parseUnary`（`:2747`）无对应臂 ⇒ `Unexpected token in expression`
#     子支 C2 `$o = NEW C();` = 赋值右侧要求分号 ⇒ `unexpected identifier, expecting ";"`
#     ⇒ 与 A 支的**软分号**形成对照：**同一份文法在赋值处硬、在语句处软**（`:2410` 是唯一放宽点）
#   D 类（**臂无条件执行**）`if (...) {A} ELSE {B}`
#     = parseIf 只认 `.k_else` token ⇒ 链在 then 臂后正常闭合；`ELSE` 走 A 支成零指令语句；
#       紧随的 `{B}` 由 `parser.zig:473 .l_brace => parseBlock` 接成**独立块语句**
#     ⇒ 发射面 = `php_echo(B)` 落在 `if (reg.toBool()) {…}` **之外**（实测 m_else_upper：then 臂在 :69 的
#        `if (reg_3.toBool())` 内，`i=le` 的 `php_echo(reg_6)` 在 :93 顶层）
#   E 类（**偶然等值，非免疫**）`$t = TRUE;`
#     = 大写 TRUE 同样失配 → `.variable "TRUE"` → 发射 `getGlobalVar("TRUE")`（实测 m_true_upper）
#     → 命中运行期**大写键**内置常量表 `runtime_lib_template.zig:7614-7615/7637`
#       （`.{ .name = "TRUE" }`、`.{ .name = "FALSE" }`、`dupe("NULL")`）⇒ 输出恰好对
#     ⇒ **键只有大写一种拼写** ⇒ 预测 Title  case `True` 必落空（本门 m_true_title 即验此预测）
#     ⇒ 结论：本族唯一「看起来正常」的档，实为两处独立缺陷（词法大小写敏感 × 常量表单拼写键）**互抵消**
#
# 判读口径：
#   1) 等值 = 归一化合并 stdout+stderr 逐字节；exit 码只记录不判等
#   2) 发射面三列（从 KEEP_TEMP 的 main.zig 直接数，不看源码推测）：
#      instr = `setSourceLocation("<本形源文件>"` 出现次数  ⇒ **0 ⇒ 该形整体从未发射（A 类铁证）**
#      echo_ = `php_echo(` 出现次数
#      gvar  = `getGlobalVar("<大写名>")` 实参字面量（E 类判据）
#      call_ = `Call to undefined function` 运行侧文本（B 类判据）
#   3) 控制臂必须始终 SAME 且 instr>0：`m_echo_bare_ctl`（小写 echo）、`m_true_lower_ctl`、
#      `m_else_ctl` ⇒ 三者锁定「通道本身可用」，红形不可归因于门坏掉
#   4) 每形独立文件、独立编译、纯直线语句、无 if/elseif 链（CODEGEN-008 零发射面）；
#      函数名/类名逐形专属（进程级全局注册表）
#   5) 产物名 aot_compile_*，不落在源目录；KEEP_TEMP 目录本门自取自删
#   6) 本门**只测不修**：`--compile` 遇 Parse error 仍 rc=0 且无产物 ⇒ 编译失败判据取「产物不可执行」
set -u
cd "$(dirname "$0")/../.." || exit 1
BIN="zig-out/bin/php-interpreter"
PHP="/opt/homebrew/bin/php"
OUT="fuzzy_scripts_720/tmp/c010_mechanism_tmp.tsv"
T=$(mktemp -d /tmp/c010mech.XXXXXX)
trap 'rm -rf "$T"' EXIT
START=$(date +%s)

norm() { sed -E -e 's/[[:space:]]*$//' -e 's|/[^[:space:]:]*\.php:[0-9]+|FILE:LINE|g' -e 's| in [^ ]*\.php on line [0-9]+| in FILE:LINE|g' -e '/^Stack trace:/,$d' -e '/^$/d'; }

body_for() {
  case "$1" in
    # A 类 vs B 类：同语义只差一对括号
    m_echo_bare_ctl)  printf '%s\n' 'echo "A\n";' ;;
    m_echo_bare_title) printf '%s\n' 'Echo "A\n";' ;;
    m_echo_paren_title) printf '%s\n' 'Echo ("A\n");' ;;
    # E 类：常量表键的拼写覆盖面
    m_true_lower_ctl) printf '%s\n' '$t1 = true;' 'echo "t=", var_export($t1, true), "\n";' ;;
    m_true_upper)     printf '%s\n' '$t2 = TRUE;' 'echo "t=", var_export($t2, true), "\n";' ;;
    m_true_title)     printf '%s\n' '$t3 = True;' 'echo "t=", var_export($t3, true), "\n";' ;;
    # D 类：ELSE 臂是否落在 if 之外
    m_else_ctl)   printf '%s\n' '$x1 = 5;' 'if ($x1 > 0) { echo "P\n"; } else { echo "Q\n"; }' ;;
    m_else_upper) printf '%s\n' '$x2 = 5;' 'if ($x2 > 0) { echo "P\n"; } ELSE { echo "Q\n"; }' ;;
    *) printf '' ;;
  esac
}

{ echo "# compiler_md5=$(md5 -q "$BIN")"
  echo "# lexer_md5=$(md5 -q src/compiler/lexer.zig)"
  echo "# keyword_lookup_md5=$(md5 -q src/compiler/keyword_lookup.zig)"
  echo "# parser_md5=$(md5 -q src/compiler/parser.zig)"
  echo "# runtime_lib_template_md5=$(md5 -q src/aot/runtime_lib_template.zig)"
  echo "# columns: shape|php_rc|aot_rc|verdict|php_norm||aot_norm||instr|echo_calls|gvar|undef_fn"
} > "$OUT"

COUNT=0; SAME_N=0; DIFF_N=0; ZERO_N=0; CF_N=0

# 固化坑（首跑踩到）：KEEP_TEMP 目录**必须在抽取生成码之后**再删，否则 instr/echo 列恒为 0
cleanup_gen() {
  for d in $(ls -d .zigphp_aot_build_* 2>/dev/null | tr '\n' ' '); do
    case " $BEFORE " in *" $d "*) ;; *) [ -n "$d" ] && rm -rf "$d" ;; esac
  done
}

for s in m_echo_bare_ctl m_echo_bare_title m_echo_paren_title \
         m_true_lower_ctl m_true_upper m_true_title \
         m_else_ctl m_else_upper; do
  COUNT=$((COUNT + 1))
  SRC="$T/c010_${s}_tmp.php"
  printf '<?php\n' > "$SRC"
  body_for "$s" >> "$SRC"

  BEFORE=$(ls -d .zigphp_aot_build_* 2>/dev/null | tr '\n' ' ')
  timeout 120 env ZIGPHP_AOT_KEEP_TEMP=1 "$BIN" --compile --output="$T/aot_compile_c010_${s}_tmp" "$SRC" >"$T/$s.compile.log" 2>&1
  GEN=""
  for d in $(ls -d .zigphp_aot_build_* 2>/dev/null | tr '\n' ' '); do
    case " $BEFORE " in *" $d "*) continue ;; esac
    [ -z "$d" ] && continue
    if [ -f "$d/main.zig" ]; then GEN="$d/main.zig"; break; fi
  done

  if [ ! -x "$T/aot_compile_c010_${s}_tmp" ]; then
    cleanup_gen
    echo "$s|php_rc=NA|aot_rc=NA|COMPILE_FAIL|- $(tail -2 "$T/$s.compile.log" | tr '\n' '|')|||instr=NA|echo=NA|gvar=NA|undef=NA" >> "$OUT"
    CF_N=$((CF_N + 1))
    continue
  fi

  # 固化坑（首跑踩到）：生成码里 setSourceLocation 嵌的是 realpath（macOS 下 /tmp → /private/tmp），
  # 拿 mktemp 返回的路径去 grep 会 0 命中
  RSRC="$(cd "$T" && pwd -P)/c010_${s}_tmp.php"
  INSTR=0; ECHOC=0; GV="none"
  if [ -n "$GEN" ]; then
    INSTR=$(grep -c "setSourceLocation(\"$RSRC\"" "$GEN" || true)
    [ -z "$INSTR" ] && INSTR=0
    ECHOC=$(grep -c 'php_echo(' "$GEN" || true)
    [ -z "$ECHOC" ] && ECHOC=0
    GV=$(grep -oE 'getGlobalVar\("[A-Za-z_]+"\)' "$GEN" | head -3 | tr '\n' '/' | sed 's|/$||')
    [ -z "$GV" ] && GV="none"
  fi
  cleanup_gen
  [ "$INSTR" = "0" ] && ZERO_N=$((ZERO_N + 1))

  timeout 10 "$PHP" "$SRC" >"$T/$s.php.out" 2>&1; prc=$?
  timeout 10 "$T/aot_compile_c010_${s}_tmp" >"$T/$s.aot.out" 2>&1; arc=$?
  php_n=$(norm < "$T/$s.php.out" | tr '\n' '|')
  aot_n=$(norm < "$T/$s.aot.out" | tr '\n' '|')
  if [ "$php_n" = "$aot_n" ]; then v=SAME; SAME_N=$((SAME_N + 1)); else v=DIFF; DIFF_N=$((DIFF_N + 1)); fi
  UDF=$(grep -oE 'Call to undefined function [A-Za-z_]+' "$T/$s.aot.out" 2>/dev/null | head -1)
  [ -z "$UDF" ] && UDF="none"
  echo "$s|php_rc=$prc|aot_rc=$arc|$v|$php_n||aot=$aot_n||instr=$INSTR|echo=$ECHOC|gvar=$GV|undef=$UDF" >> "$OUT"
done

echo "ELAPSED=$(($(date +%s) - START))s" >> "$OUT"
echo "C010MECH_DONE shapes=$COUNT same=$SAME_N diff=$DIFF_N zero_instr=$ZERO_N compile_fail=$CF_N" >> "$OUT"
cat "$OUT"
