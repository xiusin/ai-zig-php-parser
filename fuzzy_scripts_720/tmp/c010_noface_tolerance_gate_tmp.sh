#!/usr/bin/env bash
# 永久侧门 H2（任务 #120 → 工单 AOT-CODEGEN-010 侧门 H 的 **NOFACE 成因判别轮**，2026-10-07）：
#   侧门 H 实测 79 形中 **15 形混合大小写臂仍与 PHP 逐字节等值（NOFACE）**。
#   但全树**不存在**任何大小写折叠通道（实测：`grep -n 'eqlIgnoreCase|ascii.lower|toLower|std.ascii' src/compiler/*.zig`
#   ⇒ 仅命中 `isAlphabetic/isAlphanumeric/isDigit` 等**字符类判断**，零处大小写比较）
#   ⇒ 这 15 形**不可能**经关键字查表命中 ⇒ 必走「坍成 t_string 之后被文法位接受」这条路。
#
# 本门用**同位换瞎词**判别：把 15 形的关键字位替换成语法上不存在的标识符 `Zkwhq`，
#   再与 PHP 真值对照 ⇒
#     over_accept   = PHP 报错而 AOT 正常输出 ⇒ 该文法位对**任意标识符 token** 宽容
#                     ⇒ 侧门 H 的 NOFACE 绿是「宽容得绿」，**不是**「已正确支持大小写」
#     strict_same   = PHP 与 AOT 同错且逐字节等值 ⇒ 该位严格 ⇒ NOFACE 另有成因，须继续归因
#     both_reject   = AOT 编译/运行拒绝**且 PHP 同拒** ⇒ **收敛**（修复把错接受转成正确拒绝），**不是红**
#     aot_only_red  = PHP 通过而 AOT 拒（编译面 AOT_ONLY_RED_COMPILE / 运行面 AOT_ONLY_RED_RUN）⇒ **硬守卫列，必须恒 0**
#     php_ok_aot_diff = PHP 通过且 AOT 也跑通但输出不同
#   ★ 判别力说明：本门**不比 AOT 与 PHP 谁对**，只比「AOT 是否接受 PHP 不接受的东西」；
#     但「AOT 拒」必须再判一次方向（both_reject vs aot_only_red），否则收敛会被读成新增红（2026-10-09 R-3 批踩过）。
#   ★ 上方第 4-6 行「全树无大小写折叠通道」＝ R-2 前的建门依据；当代次已有 `case_insensitive_keywords` 旗标，
#     本门判的仍是**与大小写无关的文法位宽容**（同位换瞎词），故形集与判据在 R-2/R-3 后代次依旧有效。
set -u
cd "$(dirname "$0")/../.." || exit 1
BIN="zig-out/bin/php-interpreter"
PHP="/opt/homebrew/bin/php"
OUT="fuzzy_scripts_720/tmp/c010_noface_tolerance_tmp.tsv"
# 冒烟通道：ONLY=n_do,n_else 只跑列出形，且**改写 smoke 专用 TSV** ⇒ 绝不覆盖全量读数
ONLY="${ONLY:-}"
if [ -n "$ONLY" ]; then OUT="fuzzy_scripts_720/tmp/c010_noface_tolerance_smoke_tmp.tsv"; fi
T=$(mktemp -d /tmp/c010h2.XXXXXX)
trap 'rm -rf "$T"' EXIT
START=$(date +%s)

norm() { sed -E -e 's/[[:space:]]*$//' -e 's|/[^[:space:]:]*\.php:[0-9]+|FILE:LINE|g' -e 's| in [^ ]*\.php on line [0-9]+| in FILE:LINE|g' -e '/^Stack trace:/,$d' -e '/^=== PHP Interpreter Performance Statistics ===$/,$d' -e '/^$/d'; }
# 与门 J :54 逐字同口径 ⇒ 编译失败支的 AOT 报错原文也能入表（否则本门最需要的证据只剩 <none>）
normlog() { norm | sed -E -e 's/^Error: //' -e 's/ on line [0-9]+$/ on line LINE/' -e 's|/tmp/[^ :]+|TMPDIR|g'; }

# 15 枚 NOFACE 形：模板取自侧门 H 的 specs（逐字一致），关键字位仍用 @KW@
noface_specs() {
  cat <<'SPEC'
n_do|@KW@ { echo "do_ok"; } while (false);
n_else|if (1 > 2) { echo "e1"; } @KW@ { echo "else_ok"; }
n_void|function kwh_vf1(): @KW@ { echo "void_ok"; } kwh_vf1();
n_const|@KW@ KWH_C1 = 5; echo KWH_C1;
n_final|@KW@ class KwhFi1 {} echo (new KwhFi1() instanceof KwhFi1) ? "final_ok" : "x";
n_mixed|function kwh_mx1(): @KW@ { return 7; } echo kwh_mx1();
n_never|function kwh_nv1(): @KW@ { throw new Exception("never_ok"); } try { kwh_nv1(); } catch (Exception $e) { echo $e->getMessage(); }
n_public|class KwhPu1 { @KW@ $x = 4; } echo (new KwhPu1())->x;
n_global|$G = 10; function kwh_gl1() { @KW@ $G; echo $G; } kwh_gl1();
n_object|function kwh_ob1(): @KW@ { return new stdClass(); } echo is_object(kwh_ob1()) ? "object_ok" : "x";
n_private|class KwhPr1 { @KW@ $v = 11; public function get(): int { return $this->v; } } echo (new KwhPr1())->get();
n_finally|try { echo "x"; } catch (Exception $e) { echo "y"; } @KW@ { echo "finally_ok"; }
n_namespace|@KW@ KwhNs1; echo 20;
n_endif|if (1 > 0): echo "endif_ok"; @KW@;
n_endswitch|switch (1): case 1: echo "s"; break; @KW@;
SPEC
}

{ echo "# compiler_md5=$(md5 -q "$BIN")"
  echo "# lexer_md5=$(md5 -q src/compiler/lexer.zig)"
  echo "# keyword_lookup_md5=$(md5 -q src/compiler/keyword_lookup.zig)"
  echo "# parser_md5=$(md5 -q src/compiler/parser.zig)"
  echo "# nonsense_spelling=Zkwhq"
  echo "# columns: shape|php_rc|aot_rc|verdict|php_norm||aot_norm（AOT 拒绝支为 aot_log=…，取自编译日志归一原文）"
  echo "# verdicts: SAME_BOTH_ERROR_LIKE / OVER_ACCEPT / DIFF_PHP_OK_AOT_DIFF / BOTH_REJECT(收敛：两侧同拒) / AOT_ONLY_RED_*PHP 通过而 AOT 拒(硬守卫，须 0)"
} > "$OUT"

CNT=0; OA=0; STRICT=0; CF=0; BOTHOK=0; BR=0; AOR=0
while IFS='|' read -r sid stpl; do
  [ -z "$sid" ] && continue
  if [ -n "$ONLY" ]; then
    case ",$ONLY," in
      *",$sid,"*) ;;
      *) continue ;;
    esac
  fi
  CNT=$((CNT + 1))
  body="${stpl//@KW@/Zkwhq}"
  SRC="$T/c010h2_${sid}_tmp.php"
  printf '<?php\n' > "$SRC"
  printf '%s\n' "$body" >> "$SRC"

  timeout 10 "$PHP" "$SRC" >"$T/$sid.php.out" 2>&1; prc=$?
  php_n=$(norm < "$T/$sid.php.out" | tr '\n' '|')

  timeout 120 "$BIN" --compile --output="$T/aot_compile_c010h2_${sid}_tmp" "$SRC" >"$T/$sid.clog" 2>&1
  php_err=0
  if [ "$prc" != 0 ] || grep -qE 'Parse error|syntax error|Fatal error' "$T/$sid.php.out"; then php_err=1; fi
  if [ ! -x "$T/aot_compile_c010h2_${sid}_tmp" ]; then
    aot_l=$(normlog < "$T/$sid.clog" | tr '\n' '|')
    # ★ 判向：AOT 拒 ≠ 红。PHP 同拒 ⇒ 收敛（BOTH_REJECT）；PHP 通过而 AOT 拒 ⇒ 真回归（硬守卫列）
    if [ "$php_err" = 1 ]; then
      echo "$sid|php_rc=$prc|aot_rc=NA|BOTH_REJECT|$php_n||aot_log=$aot_l" >> "$OUT"
      BR=$((BR + 1)); CF=$((CF + 1))
    else
      echo "$sid|php_rc=$prc|aot_rc=NA|AOT_ONLY_RED_COMPILE|$php_n||aot_log=$aot_l" >> "$OUT"
      AOR=$((AOR + 1)); CF=$((CF + 1))
    fi
    continue
  fi
  timeout 10 "$T/aot_compile_c010h2_${sid}_tmp" >"$T/$sid.aot.out" 2>&1; arc=$?
  aot_n=$(norm < "$T/$sid.aot.out" | tr '\n' '|')

  if [ "$php_n" = "$aot_n" ]; then
    v=SAME_BOTH_ERROR_LIKE; STRICT=$((STRICT + 1))
  elif [ "$php_err" = 1 ]; then
    v=OVER_ACCEPT; OA=$((OA + 1))
  else
    v=DIFF_PHP_OK_AOT_DIFF; BOTHOK=$((BOTHOK + 1))
    if [ "$arc" != 0 ] || grep -qE 'Fatal error|Parse error' "$T/$sid.aot.out"; then AOR=$((AOR + 1)); v=AOT_ONLY_RED_RUN; fi
  fi
  echo "$sid|php_rc=$prc|aot_rc=$arc|$v|$php_n||aot=$aot_n" >> "$OUT"
done < <(noface_specs)

RESID=$(ls -d .zigphp_aot_build_* 2>/dev/null | wc -l | tr -d ' ')
echo "ELAPSED=$(($(date +%s) - START))s" >> "$OUT"
echo "C010H2_DONE shapes=$CNT over_accept=$OA strict_same=$STRICT aot_compile_fail=$CF both_reject=$BR aot_only_red=$AOR php_ok_aot_diff=$BOTHOK repo_build_residue=$RESID SMOKE_ONLY=${ONLY:-0}" >> "$OUT"
cat "$OUT"
