#!/usr/bin/env bash
# 永久侧门 J（工单 AOT-CODEGEN-010 §7-15 收口轮，2026-10-08）：替代语法（`endif;`/`endwhile;`/`endfor;`/
#   `endforeach;`/`endswitch;` 族）的**真实支持性**正负例实测。
#
# 背景（读码实测，非推测）：parser.zig 存在完整 is_alternative 支路
#   if        :1495-1518（endif 为**软消耗** `if (self.curr.tag == .k_endif)`）
#   parseAlternativeBody :1592-1599（停在 end_tag / eof；end_tag==.k_endif 时另停 elseif/else）
#   while     :1577-1583（endwhile 为**硬 eat**）
#   foreach   :1671-1672 / for :1832-1833（硬 eat）
#   switch    :3531/3562-3567（endswitch 软消耗；循环体 :3557-3559 对意外 token `nextToken()` 跳过）
#   ⇒ 五支路产出**标准 AST 节点**（.if_stmt/.while_stmt/.for_stmt/.foreach_stmt/.switch_stmt）⇒ 发射侧语法无关。
#   但「解析接受」≠「语义正确」，且三处软硬不对称会不会让 AOT **接受 PHP 拒绝的写法**，
#   此前只登记为 ⚠️ 推断未取证（交接文档 §4.4 / §7-15）⇒ 本门取证。
#
# 判据（承侧门 H2 的三类判读 + 本门两类）：
#   SAME / DIFF                = PHP 与 AOT 均成功，逐字节规范化输出等 / 不等
#   BOTH_REJECT                = PHP 报错且 AOT 拒绝编译（产物不可执行）⇒ 该位严格，两侧一致
#   OVER_ACCEPT                = PHP 报错但 AOT 编译成功 ⇒ AOT 比 PHP 宽容（负例面）
#   AOT_ONLY_RED               = PHP 正常但 AOT 拒绝编译 ⇒ 真功能缺口（正例面致命）
#   RUN_RED / BOTH_ERR_DIFF    = AOT 运行 rc≠0（PHP 正常）/ 两侧都错但错误类别不同
#   ★ 编译失败判据取「产物不可执行」不取 rc（记忆规则 21：--compile 解析失败仍 rc=0 且无产物）
#
# 修门记录（v1→v2，先修门、后引用；v1 读数只在「verdict/rc」两列可比，数据列禁止引用）：
#   ① **列契约被破**：v1 用 `tr '\n' '|'` 把多行输出接成一行，而列分隔符本身是 `|` ⇒ PHP 的
#      Parse error 在 CLI 下打**两行**（`PHP Parse error: …` + 裸 `Parse error: …`），故 v1 所有
#      报错行的第 5 列**溢出到第 6、7 列**（`awk -F'|' '{print NF}'` 实测：7 枚 `n_*` 行 **NF=9**、
#      16 枚 `p_*` 行 NF=7，而表头声明 7 列）。v2 改为以字面量 `\n` 连接。
#   ② **AOT 侧错误文本丢失**：v1 的 compile_fail 支只写 `<compile_fail>`，且成功支随后 `rm` 掉 `.clog`
#      ⇒ 本门最需要的证据（AOT 到底在哪一位报错）不在表内，须另跑单形复现（本轮实测：
#      `n_colon_brace_mix` 的 AOT 原文 = `unexpected end of file, expecting "}"`，与 PHP 的
#      `unexpected token "endif"` **报错点不同**，v1 表无法自证）。v2 把归一化后的 clog 写入 aot 列。
#
# 纪律：仓库根执行；全命令带 timeout；产物名 aot_compile_*；KEEP_TEMP 不需要（只比运行输出）；
#   .php 探针写在 mktemp 目录并随 trap 删除，语料 .php 源零删除（§七-9）；零 src/ 改动。
#   冒烟通道 ONLY=p_if,n_if_no_endif ⇒ 改写 .smoke.tsv，**绝不覆盖**注册读数表。
set -u
cd "$(dirname "$0")/../.." || exit 1
BIN="zig-out/bin/php-interpreter"
PHP="/opt/homebrew/bin/php"
OUT="fuzzy_scripts_720/tmp/c010_alt_syntax_gate_tmp.tsv"
ONLY="${ONLY:-}"
if [ -n "$ONLY" ]; then OUT="fuzzy_scripts_720/tmp/c010_alt_syntax_smoke_tmp.tsv"; fi
T=$(mktemp -d /tmp/c010j.XXXXXX)
trap 'rm -rf "$T"' EXIT
START=$(date +%s)

norm() { sed -E -e 's/[[:space:]]*$//' -e 's|/[^[:space:]:]*\.php:[0-9]+|FILE:LINE|g' -e 's| in [^ ]*\.php on line [0-9]+| in FILE:LINE|g' -e '/^Stack trace:/,$d' -e '/^=== PHP Interpreter Performance Statistics ===$/,$d' -e '/^$/d'; }

# v2 修门 ①：多行输出以字面量 \n 连接，**不得**用 `tr '\n' '|'`（与列分隔符冲突 ⇒ 列溢出）
jlines() { norm | awk '{printf "%s\\n", $0}'; }

# v2 修门 ②：编译日志专用归一（AOT 报错无文件路径，只有 `on line N`；临时目录绝对路径必须折叠，
#   否则同一形跨 run / 跨机器逐字节不等 ⇒ 不能当注册读数）
normlog() { norm | sed -E -e 's/^Error: //' -e 's/ on line [0-9]+$/ on line LINE/' -e 's|/tmp/[^ :]+|TMPDIR|g'; }

alt_specs() {
  cat <<'SPEC'
p_if|if (1 > 0): echo "A"; endif;
p_if_else|if (0): echo "A"; else: echo "B"; endif;
p_if_elseif_else|if (0): echo "A"; elseif (0): echo "B"; else: echo "C"; endif;
p_if_elseif_mid|if (0): echo "A"; elseif (1): echo "B"; elseif (1): echo "C"; else: echo "D"; endif;
p_while|$i = 0; while ($i < 3): echo $i; $i++; endwhile;
p_for|for ($i = 0; $i < 3; $i++): echo $i; endfor;
p_foreach|foreach ([1, 2, 3] as $v): echo $v; endforeach;
p_foreach_kv|foreach (["a" => 1, "b" => 2] as $k => $v): echo $k, "=", $v, ";"; endforeach;
p_switch_case|switch (2): case 1: echo "one"; break; case 2: echo "two"; break; default: echo "d"; endswitch;
p_switch_default|switch (9): case 1: echo "one"; break; default: echo "dflt"; endswitch;
p_nested_if_foreach|if (1 > 0): foreach ([1, 2] as $v): if ($v > 1): echo "G"; endif; endforeach; endif;
p_alt_in_block|foreach ([1, 2] as $v) { if ($v == 2): echo "K"; endif; }
p_fn_return_alt|function kwh_j_f(): string { if (true): return "R"; endif; return "N"; } echo kwh_j_f();
p_break_in_alt_while|while (true): echo "X"; break; endwhile;
p_alt_multi_stmt|if (1): $s = 0; for ($i = 1; $i <= 3; $i++): $s += $i; endfor; echo $s; endif;
p_alt_top_and_tail|if (1): echo "Z"; endif; echo "!";
p_if_elseif_multi|if (0): echo "A"; elseif (1): $s = 1; $s += 2; echo $s; endif;
p_if_else_multi|if (0): echo "A"; else: $t = 2; $t *= 5; echo $t; endif;
p_if_elseif_chain_multi|if (0): echo "A"; elseif (0): echo "B"; else: $u = 1; $u++; echo $u; endif;
n_if_no_endif|if (1 > 0): echo "P";
n_endif_alone|endif;
n_while_no_endwhile|while (false): echo "Q";
n_switch_no_endswitch|switch (1): case 1: echo "S"; break;
n_mismatch_end|if (1): echo "T"; endwhile;
n_colon_brace_mix|if (1) { echo "U"; endif;
n_double_endif|if (1): echo "V"; endif; endif;
n_switch_stmt_before_case_alt|switch (1): echo "W"; endswitch;
n_else_no_endif|if (0): echo "A"; else: echo "B";
n_elseif_no_endif|if (0): echo "A"; elseif (1): echo "B";
SPEC
}

{ echo "# compiler_md5=$(md5 -q "$BIN")"
  echo "# lexer_md5=$(md5 -q src/compiler/lexer.zig)"
  echo "# keyword_lookup_md5=$(md5 -q src/compiler/keyword_lookup.zig)"
  echo "# parser_md5=$(md5 -q src/compiler/parser.zig)"
  echo "# gate_rev=v3 (v3=R-3 严格闭合落地轮 +6 形守卫面；v2=69806529…/表 8b208dd0…，已入 git HEAD 可取回；v1 数据列禁止引用)"
  echo "# positive_shapes=19 negative_shapes=10"
  echo "# columns: shape|php_rc|aot_rc|verdict|php_norm||aot_norm(或 <compile_fail> aot_log=…)"
  echo "# 行内多行输出以字面量 \n 连接"
} > "$OUT"

CNT=0; SAME=0; DIFF=0; OA=0; BOTH=0; AOR=0; RUNR=0; BED=0
while IFS='|' read -r sid body; do
  [ -z "$sid" ] && continue
  if [ -n "$ONLY" ]; then
    case ",$ONLY," in
      *",$sid,"*) ;;
      *) continue ;;
    esac
  fi
  CNT=$((CNT + 1))
  SRC="$T/c010j_${sid}_tmp.php"
  printf '<?php\n%s\n' "$body" > "$SRC"

  timeout 10 "$PHP" "$SRC" >"$T/$sid.php.out" 2>&1; prc=$?
  php_n=$(norm < "$T/$sid.php.out" | jlines)
  php_err=0
  if [ "$prc" != 0 ] || grep -qE 'Parse error|syntax error|Fatal error' "$T/$sid.php.out"; then php_err=1; fi

  timeout 120 "$BIN" --compile --no-debug-info --output="$T/aot_compile_c010j_${sid}_tmp" "$SRC" >"$T/$sid.clog" 2>&1
  if [ ! -x "$T/aot_compile_c010j_${sid}_tmp" ]; then
    if [ "$php_err" = 1 ]; then
      v=BOTH_REJECT; BOTH=$((BOTH + 1))
    else
      v=AOT_ONLY_RED; AOR=$((AOR + 1))
    fi
    aot_log_n=$(normlog < "$T/$sid.clog" | jlines)
    echo "$sid|php_rc=$prc|aot_rc=NA|$v|$php_n||<compile_fail> aot_log=$aot_log_n" >> "$OUT"
    continue
  fi
  timeout 10 "$T/aot_compile_c010j_${sid}_tmp" >"$T/$sid.aot.out" 2>&1; arc=$?
  rm -f "$T/aot_compile_c010j_${sid}_tmp" "$T/$sid.clog"
  aot_n=$(norm < "$T/$sid.aot.out" | jlines)

  if [ "$php_err" = 1 ]; then
    if [ "$php_n" = "$aot_n" ]; then v=BOTH_ERROR_SAME; BOTH=$((BOTH + 1))
    elif [ "$arc" != 0 ]; then v=BOTH_ERROR_DIFF; BED=$((BED + 1))
    else v=OVER_ACCEPT; OA=$((OA + 1)); fi
  else
    if [ "$arc" != 0 ]; then v=RUN_RED; RUNR=$((RUNR + 1))
    elif [ "$php_n" = "$aot_n" ]; then v=SAME; SAME=$((SAME + 1))
    else v=DIFF; DIFF=$((DIFF + 1)); fi
  fi
  echo "$sid|php_rc=$prc|aot_rc=$arc|$v|$php_n||aot=$aot_n" >> "$OUT"
done < <(alt_specs)

RESID=$(ls -d .zigphp_aot_build_* 2>/dev/null | wc -l | tr -d ' ')
echo "ELAPSED=$(($(date +%s) - START))s" >> "$OUT"
echo "C010J_DONE shapes=$CNT same=$SAME diff=$DIFF over_accept=$OA both_reject=$BOTH aot_only_red=$AOR run_red=$RUNR both_err_diff=$BED repo_build_residue=$RESID SMOKE_ONLY=${ONLY:-0}" >> "$OUT"
tail -1 "$OUT"
