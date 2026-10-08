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
#     strict_both   = PHP 与 AOT 同错（逐字节等值）⇒ 该位严格 ⇒ NOFACE 另有成因，须继续归因
#     aot_compile_fail = AOT 拒绝 ⇒ 该位严格
#   ★ 判别力说明：本门**不比 AOT 与 PHP 谁对**，只比「AOT 是否接受 PHP 不接受的东西」
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
  echo "# nonsense_spelling=Zkwhq"
  echo "# columns: shape|php_rc|aot_rc|verdict|php_norm||aot_norm"
} > "$OUT"

CNT=0; OA=0; STRICT=0; CF=0; BOTHOK=0
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
  if [ ! -x "$T/aot_compile_c010h2_${sid}_tmp" ]; then
    echo "$sid|php_rc=$prc|aot_rc=NA|AOT_COMPILE_FAIL|$php_n||<none>" >> "$OUT"
    CF=$((CF + 1))
    continue
  fi
  timeout 10 "$T/aot_compile_c010h2_${sid}_tmp" >"$T/$sid.aot.out" 2>&1; arc=$?
  aot_n=$(norm < "$T/$sid.aot.out" | tr '\n' '|')

  php_err=0
  if [ "$prc" != 0 ] || grep -qE 'Parse error|syntax error|Fatal error' "$T/$sid.php.out"; then php_err=1; fi
  if [ "$php_n" = "$aot_n" ]; then
    v=SAME_BOTH_ERROR_LIKE; STRICT=$((STRICT + 1))
  elif [ "$php_err" = 1 ]; then
    v=OVER_ACCEPT; OA=$((OA + 1))
  else
    v=DIFF_PHP_OK_AOT_DIFF; BOTHOK=$((BOTHOK + 1))
  fi
  echo "$sid|php_rc=$prc|aot_rc=$arc|$v|$php_n||aot=$aot_n" >> "$OUT"
done < <(noface_specs)

RESID=$(ls -d .zigphp_aot_build_* 2>/dev/null | wc -l | tr -d ' ')
echo "ELAPSED=$(($(date +%s) - START))s" >> "$OUT"
echo "C010H2_DONE shapes=$CNT over_accept=$OA strict_same=$STRICT aot_compile_fail=$CF php_ok_aot_diff=$BOTHOK repo_build_residue=$RESID SMOKE_ONLY=${ONLY:-0}" >> "$OUT"
cat "$OUT"
