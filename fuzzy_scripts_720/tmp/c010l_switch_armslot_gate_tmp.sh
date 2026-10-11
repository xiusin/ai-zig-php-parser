#!/usr/bin/env bash
# 永久侧门 L（工单 AOT-CODEGEN-010 面 A 落地前置守卫门，2026-10-09，任务 #127）：
#   **花括号 switch 的「臂表位」**（= 首个 `case`/`default`/`}` 之前，以及两臂之间的列表位）
#   上各类 token 的 **PHP 合法性穷举** ⇒ 本门的用途是给 R-5 的「收紧拒绝」量**过度拒绝面**，
#   不是复证门 K 的宽容面（门 K 已注册 24 形读数，禁改，规则 11）。
#
# 落地位置（读码实测，代次 parser_md5 见表头）：
#   `parseSwitch` 意外 token 支 `src/compiler/parser.zig:3592-3597` ＝
#       if (is_alternative and self.strict_alt_closers) break;
#       self.nextToken(); // Skip unexpected tokens
#   花括号支走 `:3596` 的整枚跳过 ⇒ 非法 token 被吞、循环自然收敛到 `}` ⇒
#   `:3611 _ = try self.eat(.r_brace);` 仍成立 ⇒ **AOT rc=0 且空输出**（门 K 4 枚 OVER_ACCEPT）。
#   R-5 目标形态＝意外 token 不再跳过而是停在原位，由 `:3611` 硬 eat 报错。
#
# 为什么必须先建本门（而非直接用门 K）：
#   门 K 的臂表位只放了三类（`echo` / `$s = 1;` / `endswitch`），**全部为 PHP 拒形**
#   （4 枚 OVER_ACCEPT）。若存在「PHP 收、AOT 也收」的合法臂表位形态（例如空语句 `;`、
#   裸块 `{ }`），R-5 会把它**新拒**⇒ 落地即制造 AOT_ONLY_RED。本门穷举该位的 token 类，
#   把「PHP 合法性」在落地**前**测出来，而不是落地后靠主回归碰运气。
#
# 判据（承门 H2 #125 / 门 K #126 定稿的五桶契约，逐字同口径）：
#   SAME_BOTH_ERROR_LIKE  = 归一化输出逐字节等值（含两侧同错但错类别等价的行）
#   OVER_ACCEPT           = PHP 报错而 AOT 正常跑通 ⇒ 该文法位对**非法 token** 宽容（负例面）
#   DIFF_PHP_OK_AOT_DIFF  = PHP 通过且 AOT 也跑通但输出不同
#   BOTH_REJECT           = AOT 拒绝编译**且 PHP 同拒** ⇒ **收敛**，不是红
#   AOT_ONLY_RED_COMPILE  = PHP 通过而 AOT 拒绝编译 ⇒ **硬守卫列，R-5 落地后必须恒 0**
#   AOT_ONLY_RED_RUN      = PHP 通过而 AOT 运行 rc≠0 或输出 Fatal/Parse ⇒ **硬守卫列，必须恒 0**
#   ★ 「AOT 拒 ≠ 红」＝PHP 同拒记 BOTH_REJECT
#   ★ 编译失败判据取「产物不可执行」不取 rc（记忆规则 21）
#
# 纪律：仓库根执行；全命令带 timeout；产物名 aot_compile_*；探针 .php 写在 mktemp 目录并随 trap 删除，
#   语料 .php 源零删除（§七-9）；冒烟通道 ONLY=l_semi_arm_list ⇒ 改写 .smoke.tsv，**绝不覆盖**注册表。
set -u
cd "$(dirname "$0")/../.." || exit 1
BIN="zig-out/bin/php-interpreter"
PHP="/opt/homebrew/bin/php"
OUT="fuzzy_scripts_720/tmp/c010l_switch_armslot_tmp.tsv"
ONLY="${ONLY:-}"
if [ -n "$ONLY" ]; then OUT="fuzzy_scripts_720/tmp/c010l_switch_armslot_smoke_tmp.tsv"; fi
T=$(mktemp -d /tmp/c010l.XXXXXX)
trap 'rm -rf "$T"' EXIT
START=$(date +%s)

norm() { sed -E -e 's/[[:space:]]*$//' -e 's|/[^[:space:]:]*\.php:[0-9]+|FILE:LINE|g' -e 's| in [^ ]*\.php on line [0-9]+| in FILE:LINE|g' -e '/^Stack trace:/,$d' -e '/^=== PHP Interpreter Performance Statistics ===$/,$d' -e '/^$/d'; }
jlines() { norm | awk '{printf "%s\\n", $0}'; }
normlog() { norm | sed -E -e 's/^Error: //' -e 's/ on line [0-9]+$/ on line LINE/' -e 's|/tmp/[^ :]+|TMPDIR|g'; }

armslot_specs() {
  cat <<'SPEC'
l_ctl_case_first|switch (1) { case 1: echo "A"; break; }
l_ctl_default_first|switch (1) { default: echo "D"; }
l_ctl_empty|switch (1) { }
l_ctl_between_arms|switch (1) { case 1: echo "A"; break; echo "TAIL"; case 2: echo "B"; }
l_semi_arm_list|switch (1) { ; case 1: echo "A"; break; }
l_two_semi_arm_list|switch (1) { ;; case 1: echo "A"; break; }
l_semi_only|switch (1) { ; }
l_bare_block_arm_list|switch (1) { { } case 1: echo "A"; break; }
l_bare_block_nested|switch (1) { { echo "X"; } case 1: echo "A"; break; }
l_if_before_case|switch (1) { if (true) { echo "I"; } case 1: echo "A"; break; }
l_for_before_case|switch (1) { for ($i = 0; $i < 1; $i++) { echo "F"; } case 1: echo "A"; break; }
l_assign_before_case|switch (1) { $a = 7; case 1: echo "A"; break; }
l_var_before_case|switch (1) { $a; case 1: echo "A"; break; }
l_alt_if_before_case|switch (1) { if (true): echo "J"; endif; case 1: echo "A"; break; }
l_endif_stray|switch (1) { endif; case 1: echo "A"; break; }
l_alt_semi_arm|switch (1): ; case 1: echo "A"; endswitch;
l_alt_two_semi|switch (1): ;; case 1: echo "A"; endswitch;
l_case_before_default|switch (1) { case 1: echo "A"; break; default: echo "D"; }
l_nested_brace_inner|switch (1) { case 1: switch (2) { ; case 2: echo "N"; } break; }
l_semi_then_block|switch (1) { ; { } case 1: echo "A"; break; }
l_bare_colon_arm_list|switch (1) { : case 1: echo "A"; break; }
l_semi_between_arms|switch (1) { case 1: echo "A"; break; ; case 2: echo "B"; }
l_stray_rbrace|switch (1) { } }
SPEC
}

{ echo "# compiler_md5=$(md5 -q "$BIN")"
  echo "# lexer_md5=$(md5 -q src/compiler/lexer.zig)"
  echo "# keyword_lookup_md5=$(md5 -q src/compiler/keyword_lookup.zig)"
  echo "# parser_md5=$(md5 -q src/compiler/parser.zig)"
  echo "# gate_rev=v1 (L 族首代；R-5 落地前置守卫门。形集＝控制臂 4 + 臂表位邻形 19 = 23 形，全部以 /opt/homebrew/bin/php 实测真值归类；控制臂 l_ctl_* 为 PHP 合法形，用于捕获过度拒绝)"
  echo "# ★ 实测规则（决定 R-5 形态，php 8.5.8 直测）：case 列表首**恰好接受一枚空语句分号**，两种语法皆然——"
  echo "#   l_semi_arm_list / l_semi_only / l_alt_semi_arm php_rc=0 且臂体照常执行；"
  echo "#   l_two_semi_arm_list / l_alt_two_semi / l_semi_then_block 第二枚或后续非法 token 仍 php_rc=255"
  echo "#   ⇒ R-5 的意外 token 收紧必须「消费单枚分号、其余一律停在原位报错」，"
  echo "#     否则落地即把今日绿形新拒（= AOT_ONLY_RED_COMPILE），且 l_alt_semi_arm 的既有红无法消"
  echo "# columns: shape|php_rc|aot_rc|verdict|php_norm||aot_norm（AOT 拒绝支为 <compile_fail> aot_log=…）"
  echo "# 行内多行输出以字面量 \n 连接"
} > "$OUT"

CNT=0; SAME=0; OA=0; DIFF=0; BR=0; AOR=0; RUNR=0
while IFS='|' read -r sid stpl; do
  [ -z "$sid" ] && continue
  if [ -n "$ONLY" ]; then
    case ",$ONLY," in
      *",$sid,"*) ;;
      *) continue ;;
    esac
  fi
  CNT=$((CNT + 1))
  SRC="$T/c010l_${sid}_tmp.php"
  printf '<?php\n%s\n' "$stpl" > "$SRC"

  timeout 10 "$PHP" "$SRC" >"$T/$sid.php.out" 2>&1; prc=$?
  php_n=$(norm < "$T/$sid.php.out" | jlines)
  php_err=0
  if [ "$prc" != 0 ] || grep -qE 'Parse error|syntax error|Fatal error' "$T/$sid.php.out"; then php_err=1; fi

  timeout 120 "$BIN" --compile --no-debug-info --output="$T/aot_compile_c010l_${sid}_tmp" "$SRC" >"$T/$sid.clog" 2>&1
  if [ ! -x "$T/aot_compile_c010l_${sid}_tmp" ]; then
    aot_l=$(normlog < "$T/$sid.clog" | jlines)
    if [ "$php_err" = 1 ]; then
      echo "$sid|php_rc=$prc|aot_rc=NA|BOTH_REJECT|$php_n||<compile_fail> aot_log=$aot_l" >> "$OUT"
      BR=$((BR + 1))
    else
      echo "$sid|php_rc=$prc|aot_rc=NA|AOT_ONLY_RED_COMPILE|$php_n||<compile_fail> aot_log=$aot_l" >> "$OUT"
      AOR=$((AOR + 1))
    fi
    continue
  fi
  timeout 10 "$T/aot_compile_c010l_${sid}_tmp" >"$T/$sid.aot.out" 2>&1; arc=$?
  rm -f "$T/aot_compile_c010l_${sid}_tmp" "$T/$sid.clog"
  aot_n=$(norm < "$T/$sid.aot.out" | jlines)

  if [ "$php_err" = 1 ]; then
    if [ "$php_n" = "$aot_n" ]; then v=SAME_BOTH_ERROR_LIKE; SAME=$((SAME + 1))
    else v=OVER_ACCEPT; OA=$((OA + 1)); fi
  else
    if [ "$arc" != 0 ] || grep -qE 'Fatal error|Parse error' "$T/$sid.aot.out"; then
      v=AOT_ONLY_RED_RUN; RUNR=$((RUNR + 1)); AOR=$((AOR + 1))
    elif [ "$php_n" = "$aot_n" ]; then v=SAME_BOTH_ERROR_LIKE; SAME=$((SAME + 1))
    else v=DIFF_PHP_OK_AOT_DIFF; DIFF=$((DIFF + 1)); fi
  fi
  echo "$sid|php_rc=$prc|aot_rc=$arc|$v|$php_n||aot=$aot_n" >> "$OUT"
done < <(armslot_specs)

RESID=$(find . -maxdepth 1 \( -name '.zigphp_aot_build_*' -o -name 'aot_compile_*' \) 2>/dev/null | wc -l | tr -d ' ')
echo "ELAPSED=$(($(date +%s) - START))s" >> "$OUT"
echo "C010L_DONE shapes=$CNT same=$SAME over_accept=$OA diff_php_ok=$DIFF both_reject=$BR aot_only_red=$AOR run_red=$RUNR repo_build_residue=$RESID SMOKE_ONLY=${ONLY:-0}" >> "$OUT"
tail -1 "$OUT"
