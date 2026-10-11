#!/usr/bin/env bash
# 永久侧门 K（工单 AOT-CODEGEN-010 §7-15c 残面取证轮，2026-10-09，任务 #126）：
#   **花括号 switch** 在「首个 case/default/} 之前」的文法位宽容面。
#
# 建门依据（读码实测，非推测；parser.zig 代次 parser_md5 见下表头）：
#   parseSwitchStmt 的意外 token 支（`:3592-3597`）＝
#       if (is_alternative and self.strict_alt_closers) break;
#       self.nextToken(); // Skip unexpected tokens
#   ⇒ R-3 批把「替代语法支」转成硬闭合，但**花括号支保留旧的整枚跳过**；
#     随后 `:3611 _ = try self.eat(.r_brace);` 仍成立 ⇒
#     `switch (1) { echo "W"; }` ⇒ PHP rc=255（unexpected token "echo", expecting "case" or "default" or "}"）
#     而 AOT rc=0 且**空输出**（已登记于 §7-15c，为本门 k_stmt_before_case 形）。
#   同时 §7-15c 只给了这一枚形 ⇒ 本门**穷举邻形**：嵌套/多条语句/裸 endswitch/重复 case/
#     `case expr =>`/`case expr;`（PHP 8 已 Deprecated 但 rc=0）/空 switch/default 首臂 等，
#     并按 #125 定稿的**五桶判向**读数，禁止把「AOT 拒」直接当回归。
#
# v1 冒烟实测的新发现（非原计划，登记于此）：除 §7-15c 的花括号**宽容面**（OVER_ACCEPT）外，
#   同一函数另立一枚**相反方向的面孔**＝分号终结符 `case expr;` / `default;` ——
#   PHP 8 仅发 `Deprecated: Case statements followed by a semicolon (;)` 且 **rc=0 照常执行**，
#   而 AOT 在 `:3571`/`:3583` 的 `_ = try self.eat(.colon); // or .fat_arrow` **硬只认冒号**
#   ⇒ AOT_ONLY_RED_COMPILE（真功能缺口）。注意该处注释写的「or .fat_arrow」实测**不成立**
#   （`case 1 => echo` PHP 自己 rc=255）⇒ 注释与代码相反，见 k_case_arrow 形。
#   因此形集扩到 24 形，含 5 枚分号族正例。
#
# 判据（承门 H2 #125 代次的五桶契约，逐字同口径）：
#   SAME_BOTH_ERROR_LIKE  = 归一化输出逐字节等值（含两侧同错但错类别等价的行）
#   OVER_ACCEPT           = PHP 报错而 AOT 正常跑通 ⇒ 该文法位对**非法 token** 宽容（负例面）
#   DIFF_PHP_OK_AOT_DIFF  = PHP 通过且 AOT 也跑通但输出不同
#   BOTH_REJECT           = AOT 拒绝编译**且 PHP 同拒** ⇒ **收敛**，不是红
#   AOT_ONLY_RED_COMPILE  = PHP 通过而 AOT 拒绝编译 ⇒ **硬守卫列，必须恒 0**（真功能缺口）
#   AOT_ONLY_RED_RUN      = PHP 通过而 AOT 运行 rc≠0 或输出 Fatal/Parse ⇒ **硬守卫列，必须恒 0**
#   ★ 「AOT 拒 ≠ 红」＝PHP 同拒记 BOTH_REJECT；「旧表结构不可判向时，禁止用人工回读某一列代替修门」
#   ★ 编译失败判据取「产物不可执行」不取 rc（记忆规则 21：--compile 解析失败仍 rc=0 且无产物）
#
# 纪律：仓库根执行；全命令带 timeout；产物名 aot_compile_*；探针 .php 写在 mktemp 目录并随 trap 删除，
#   语料 .php 源零删除（§七-9）；**零 src/ 改动**（本门为落地前置取证，落地须老铁点头）。
#   冒烟通道 ONLY=k_empty,k_stmt_before_case ⇒ 改写 .smoke.tsv，**绝不覆盖**注册读数表。
set -u
cd "$(dirname "$0")/../.." || exit 1
BIN="zig-out/bin/php-interpreter"
PHP="/opt/homebrew/bin/php"
OUT="fuzzy_scripts_720/tmp/c010_brace_switch_tmp.tsv"
ONLY="${ONLY:-}"
if [ -n "$ONLY" ]; then OUT="fuzzy_scripts_720/tmp/c010_brace_switch_smoke_tmp.tsv"; fi
T=$(mktemp -d /tmp/c010k.XXXXXX)
trap 'rm -rf "$T"' EXIT
START=$(date +%s)

norm() { sed -E -e 's/[[:space:]]*$//' -e 's|/[^[:space:]:]*\.php:[0-9]+|FILE:LINE|g' -e 's| in [^ ]*\.php on line [0-9]+| in FILE:LINE|g' -e '/^Stack trace:/,$d' -e '/^=== PHP Interpreter Performance Statistics ===$/,$d' -e '/^$/d'; }
jlines() { norm | awk '{printf "%s\\n", $0}'; }
# 与门 J :54 / 门 H2 :34 逐字同口径 ⇒ AOT 拒绝支的报错原文入表（新列必须走它，否则原始日志含随机临时目录 /tmp/c010k.XXXXXX）
normlog() { norm | sed -E -e 's/^Error: //' -e 's/ on line [0-9]+$/ on line LINE/' -e 's|/tmp/[^ :]+|TMPDIR|g'; }

bs_specs() {
  cat <<'SPEC'
k_empty|switch (1) { }
k_case_colon|switch (1) { case 1: echo "C"; }
k_default_first|switch (1) { default: echo "D"; case 2: echo "C"; }
k_default_empty|switch (1) { default: }
k_fallthrough|switch (2) { case 1: case 2: echo "f"; break; default: echo "d"; }
k_case_brace_body|switch (1) { case 1: { echo "B"; } break; }
k_case_semi|switch (1) { case 1; echo "S"; }
k_case_semi_fall|switch (2) { case 1; case 2; echo "T"; }
k_default_semi|switch (1) { default; echo "D"; }
k_case_semi_alt|switch (1): case 1; echo "Q"; endswitch;
k_case_semi_two_arms|switch (3) { case 1; echo "a"; case 3; echo "b"; }
k_nested_switch|switch (1) { case 1: switch (2) { case 2: echo "N"; } break; }
k_in_for|$q = 0; for ($i = 0; $i < 3; $i++) { switch ($i) { case 1: $q += 10; break; default: $q += 1; } } echo $q;
k_break_tail|switch (1) { case 1: echo "x"; break; default: echo "y"; break; }
k_stmt_before_case|switch (1) { echo "W"; }
k_stmt_before_case_two|switch (1) { echo "W"; $s = 1; }
k_nested_stmt_head|switch (1) { case 1: switch (2) { echo "inner"; } break; }
k_stray_endswitch|switch (1) { endswitch; case 1: echo "z"; }
k_dup_case_kw|switch (1) { case case 1: echo "q"; }
k_case_arrow|switch (1) { case 1 => echo "A"; }
k_case_no_term|switch (1) { case 1 echo "A"; }
k_case_unclosed|switch (1) { case 1: echo "x";
k_alt_stmt_head|switch (1): echo "W"; endswitch;
k_alt_no_endswitch|switch (1): case 1: echo "S"; break;
SPEC
}

{ echo "# compiler_md5=$(md5 -q "$BIN")"
  echo "# lexer_md5=$(md5 -q src/compiler/lexer.zig)"
  echo "# keyword_lookup_md5=$(md5 -q src/compiler/keyword_lookup.zig)"
  echo "# parser_md5=$(md5 -q src/compiler/parser.zig)"
  echo "# gate_rev=v1 (K 族首代；形集＝正例 14 + 负例 10 = 24 形，全部以 /opt/homebrew/bin/php 实测真值归类；其中 5 枚 k_*semi* 为 PHP「Deprecated 但 rc=0」的分号终结符形)"
  echo "# columns: shape|php_rc|aot_rc|verdict|php_norm||aot_norm（AOT 拒绝支为 <compile_fail> aot_log=…）"
  echo "# 行内多行输出以字面量 \n 连接"
} > "$OUT"

CNT=0; SAME=0; OA=0; BOTHOK=0; BR=0; AOR=0; RUNR=0
while IFS='|' read -r sid stpl; do
  [ -z "$sid" ] && continue
  if [ -n "$ONLY" ]; then
    case ",$ONLY," in
      *",$sid,"*) ;;
      *) continue ;;
    esac
  fi
  CNT=$((CNT + 1))
  SRC="$T/c010k_${sid}_tmp.php"
  printf '<?php\n%s\n' "$stpl" > "$SRC"

  timeout 10 "$PHP" "$SRC" >"$T/$sid.php.out" 2>&1; prc=$?
  php_n=$(norm < "$T/$sid.php.out" | jlines)
  php_err=0
  if [ "$prc" != 0 ] || grep -qE 'Parse error|syntax error|Fatal error' "$T/$sid.php.out"; then php_err=1; fi

  timeout 120 "$BIN" --compile --no-debug-info --output="$T/aot_compile_c010k_${sid}_tmp" "$SRC" >"$T/$sid.clog" 2>&1
  if [ ! -x "$T/aot_compile_c010k_${sid}_tmp" ]; then
    aot_l=$(normlog < "$T/$sid.clog" | jlines)
    # ★ 判向：AOT 拒 ≠ 红。PHP 同拒 ⇒ 收敛（BOTH_REJECT）；PHP 通过而 AOT 拒 ⇒ 真回归（硬守卫列）
    if [ "$php_err" = 1 ]; then
      echo "$sid|php_rc=$prc|aot_rc=NA|BOTH_REJECT|$php_n||<compile_fail> aot_log=$aot_l" >> "$OUT"
      BR=$((BR + 1))
    else
      echo "$sid|php_rc=$prc|aot_rc=NA|AOT_ONLY_RED_COMPILE|$php_n||<compile_fail> aot_log=$aot_l" >> "$OUT"
      AOR=$((AOR + 1))
    fi
    continue
  fi
  timeout 10 "$T/aot_compile_c010k_${sid}_tmp" >"$T/$sid.aot.out" 2>&1; arc=$?
  rm -f "$T/aot_compile_c010k_${sid}_tmp" "$T/$sid.clog"
  aot_n=$(norm < "$T/$sid.aot.out" | jlines)

  if [ "$php_err" = 1 ]; then
    if [ "$php_n" = "$aot_n" ]; then v=SAME_BOTH_ERROR_LIKE; SAME=$((SAME + 1))
    else v=OVER_ACCEPT; OA=$((OA + 1)); fi
  else
    if [ "$arc" != 0 ] || grep -qE 'Fatal error|Parse error' "$T/$sid.aot.out"; then
      v=AOT_ONLY_RED_RUN; RUNR=$((RUNR + 1)); AOR=$((AOR + 1))
    elif [ "$php_n" = "$aot_n" ]; then v=SAME_BOTH_ERROR_LIKE; SAME=$((SAME + 1))
    else v=DIFF_PHP_OK_AOT_DIFF; BOTHOK=$((BOTHOK + 1)); fi
  fi
  echo "$sid|php_rc=$prc|aot_rc=$arc|$v|$php_n||aot=$aot_n" >> "$OUT"
done < <(bs_specs)

RESID=$(find . -maxdepth 1 \( -name '.zigphp_aot_build_*' -o -name 'aot_compile_*' \) 2>/dev/null | wc -l | tr -d ' ')
echo "ELAPSED=$(($(date +%s) - START))s" >> "$OUT"
echo "C010K_DONE shapes=$CNT same=$SAME over_accept=$OA diff_php_ok=$BOTHOK both_reject=$BR aot_only_red=$AOR run_red=$RUNR repo_build_residue=$RESID SMOKE_ONLY=${ONLY:-0}" >> "$OUT"
tail -1 "$OUT"
