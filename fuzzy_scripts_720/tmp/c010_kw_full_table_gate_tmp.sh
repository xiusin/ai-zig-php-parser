#!/usr/bin/env bash
# 永久侧门 H（任务 #120 → 工单 AOT-CODEGEN-010 §7-2 遗留项，2026-10-07）：
#   按 `src/compiler/keyword_lookup.zig:6-96` **全 87 枚表项**逐枚实测「混合大小写关键字」面，
#   给路线 R-2（查表改大小写不敏感）划出**真实验收面** —— 现有门 E（19 形）/F（8 形）/G（7 形）
#   只覆盖 10 族，其余 77 族的结局从未实测过。
#
# ★ 本门的方法学核心：**一形双臂，同模板只差拼写**
#     ctrl  臂 = 表内原拼写（关键字族为全小写；魔术常量为全大写）
#     probe 臂 = Title 大小写混合拼写（`Echo` / `True` / `__Dir__` …）
#   ⇒ 只有「**ctrl SAME ∧ probe 非 SAME**」才是本面（FACE）；
#     ctrl 本身红/编译失败 ⇒ 该形被**另一张缺陷面孔**污染（如 enum/readonly/declare 支持度），
#     一律记 CONFOUNDED，**禁止计入本面**，也禁止因此判定 R-2 无效。
#   两臂由**同一模板串**经 `${tpl//@KW@/…}` 生成 ⇒ 「只差拼写」是结构性保证，不靠人工复写。
#
# 为何 probe 一律取 Title 而非全大写：#119 实测 `TRUE`/`FALSE`/`NULL` 的全大写形
#   会经「变量名 → 大写键内置常量表」**偶然等值**（门 F `m_true_upper` SAME）⇒
#   全大写拼写对这三枚**没有判别力**；Title（`True`）实测才红。
#
# 附带第二组（role=inverse，7 形，同双臂法）：**表内非 PHP 关键字的反向面孔**
#   `keyword_lookup.zig` 含 `go/get/set/lock/with/from/struct` 七枚 **PHP 里根本不是关键字**的词
#   ⇒ 它们在 lexer 层被抢注成 token ⇒ 用户拿它们当函数名/属性名/类名时是否被误认。
#   ctrl 臂用等价改名（`zzkwhgo` 等），probe 臂用原词 ⇒ probe 红 ∧ ctrl 绿 = **过度识别面**。
#   ⚠ 该面**与大小写无关**（小写即触发）⇒ R-2 一条改动**收不了它**，须单列。
#
# 判读口径：
#   1) 等值 = 归一化合并 stdout+stderr 逐字节（norm 沿用门 E/F 口径，不采用门 G 的扩展口径）；
#      exit 码只记录不判等（规则：Debug/Release 与致命路径 exit 码不可当同一性判据）
#   2) `--compile` 遇 Parse error **仍 rc=0 且不产出二进制**（规则 21）⇒ 编译失败判据取「产物不可执行」
#   3) 编译必须在**仓库根**执行（否则 `executable generation failed: FileNotFound`，会被误读成解析失败）
#   4) 一形一文件、逐文件编译；类/函数/常量名逐形专属（进程级全局注册表）
#   5) 产物名 aot_compile_*，不落源目录；临时目录本门自取自删；**所有命令带 timeout**
#   6) 本门**只测不修**，零 `src/` 改动
#   7) **固化坑（首跑踩到 ⇒ 已加 `php -l` 前置自检）**：`k_callable` 模板原写
#      `kwh_cb1(fn(): int { return 15; })`，而 PHP 8.5.8 **自身**即报
#      `Parse error: unexpected token "{", expecting "=>"`（`fn` 只允许箭头形 `=>`，带花括号的是闭包）
#      ⇒ 两臂同错 ⇒ 该形**零判别力**，却被分类成 `CONFOUNDED_CTRL_COMPILE_FAIL`（误读成「另一张缺陷面孔」）。
#      现改为闭包形，并给**每一臂**先跑 `php -l`：任一模板被 PHP 拒绝 ⇒ 记 `BAD_PROBE_*` 且**不计入 face/confounded**。
#      ⇒ 规则：**红面归因前必须先证明探针自身是合法 PHP**，否则「AOT 也报错」可能是 AOT 的正确行为。
#      反向组 7 枚模板已逐枚 `php -l` + 实跑复验（全部 lint=0、`function go()` 等 PHP 侧均返回预期值）
#      ⇒ 该组 5 枚 `OVERRECOGNITION_FACE` **非**坏探针。首跑读数禁止引用；注册读数取自修门后的全量跑
set -u
cd "$(dirname "$0")/../.." || exit 1
BIN="zig-out/bin/php-interpreter"
PHP="/opt/homebrew/bin/php"
OUT="fuzzy_scripts_720/tmp/c010_kw_full_table_tmp.tsv"
# 自检通道：ONLY=<正则> 只跑匹配形，输出改写 .smoke.tsv 并打 SMOKE_ONLY 标记，
# 冒烟读数**禁止**当全量总数引用（规则 11 的同族坑：门 F 首跑假读数教训）
if [ -n "${ONLY:-}" ]; then OUT="fuzzy_scripts_720/tmp/c010_kw_full_table_smoke_tmp.tsv"; fi
T=$(mktemp -d /tmp/c010h.XXXXXX)
trap 'rm -rf "$T"' EXIT
START=$(date +%s)

norm() { sed -E -e 's/[[:space:]]*$//' -e 's|^PHP ||' -e 's| ?in [^ ]*\.php on line [0-9]+||g' -e 's| ?in [^ ]*\.php:[0-9]+||g' -e '/^Stack trace:/,$d' -e '/^$/d'; }

# ---------------------------------------------------------------------------
# 规格表：<id>|<ctrl 拼写>|<probe 拼写>|<模板（@KW@ 为关键字位）>
# 模板内不得出现 '|'；'@INCP@' 由本门替换为本形专属 includee 的绝对路径。
# ---------------------------------------------------------------------------
specs() {
  cat <<'SPEC'
k_fn|fn|Fn|$k = @KW@($x) => $x + 1; echo $k(2);
k_if|if|If|@KW@ (1 > 0) { echo "if_ok"; }
k_do|do|Do|@KW@ { echo "do_ok"; } while (false);
k_as|as|As|foreach ([5] @KW@ $v) { echo $v; }
k_or|or|Or|$r = (1 < 2) @KW@ (3 < 2); echo $r ? "y" : "n";
k_new|new|New|class KwhN1 { public function __construct() { echo "new_ok"; } } $o = @KW@ KwhN1();
k_for|for|For|@KW@ ($i = 0; $i < 2; $i++) { echo "f"; }
k_use|use|Use|trait KwhUT1 { public function m() { echo "use_ok"; } } class KwhUC1 { @KW@ KwhUT1; } (new KwhUC1())->m();
k_try|try|Try|@KW@ { echo "try_ok"; } catch (Exception $e) { echo "cat"; }
k_and|and|And|$r = (1 < 2) @KW@ (3 < 2); echo $r ? "y" : "n";
k_xor|xor|Xor|$r = (1 < 2) @KW@ (3 < 2); echo $r ? "y" : "n";
k_var|var|Var|class KwhV1 { @KW@ $p = 3; } echo (new KwhV1())->p;
k_else|else|Else|if (1 > 2) { echo "e1"; } @KW@ { echo "else_ok"; }
k_echo|echo|Echo|@KW@ "echo_ok";
k_case|case|Case|switch (1) { @KW@ 1: echo "case_ok"; break; }
k_true|true|True|$t = @KW@; echo $t ? "T" : "F";
k_null|null|Null|$n = @KW@; echo ($n === null) ? "N" : "X";
k_void|void|Void|function kwh_vf1(): @KW@ { echo "void_ok"; } kwh_vf1();
k_enum|enum|Enum|@KW@ KwhEn1: string { case A = "a"; } echo KwhEn1::A->value;
k_goto|goto|Goto|$i = 0; KWH_LBL1: $i++; if ($i < 2) { @KW@ KWH_LBL1; } echo $i;
k_list|list|List|@KW@ ($a, $b) = [1, 2]; echo $a + $b;
k_self|self|Self|class KwhSe1 { public static function m(): int { return 1; } public function n(): int { return @KW@::m(); } } echo (new KwhSe1())->n();
k_class|class|Class|@KW@ KwhCl1 {} echo (new KwhCl1() instanceof KwhCl1) ? "class_ok" : "x";
k_trait|trait|Trait|@KW@ KwhTe1 { public function m() { echo "trait_ok"; } } class KwhTc1 { use KwhTe1; } (new KwhTc1())->m();
k_while|while|While|$i = 0; @KW@ ($i < 2) { echo "w"; $i++; }
k_break|break|Break|for ($i = 0; $i < 5; $i++) { if ($i === 1) { @KW@; } echo "b"; }
k_catch|catch|Catch|try { echo "a"; } @KW@ (Exception $e) { echo "b"; }
k_clone|clone|Clone|$o = new stdClass(); $c = @KW@ $o; echo ($c === $o) ? "same" : "clone_ok";
k_const|const|Const|@KW@ KWH_C1 = 5; echo KWH_C1;
k_false|false|False|$f = @KW@; echo $f ? "T" : "false_ok";
k_final|final|Final|@KW@ class KwhFi1 {} echo (new KwhFi1() instanceof KwhFi1) ? "final_ok" : "x";
k_mixed|mixed|Mixed|function kwh_mx1(): @KW@ { return 7; } echo kwh_mx1();
k_never|never|Never|function kwh_nv1(): @KW@ { throw new Exception("never_ok"); } try { kwh_nv1(); } catch (Exception $e) { echo $e->getMessage(); }
k_print|print|Print|@KW@ "print_ok";
k_throw|throw|Throw|try { @KW@ new Exception("throw_ok"); } catch (Exception $e) { echo $e->getMessage(); }
k_unset|unset|Unset|$a = [1, 2]; @KW@($a[0]); echo count($a);
k_match|match|Match|echo @KW@ (1) { 1 => "match_ok", default => "d" };
k_array|array|Array|$a = @KW@ (1, 2, 3); echo count($a);
k_elseif|elseif|Elseif|if (1 > 2) { echo "a"; } @KW@ (1 < 2) { echo "elseif_ok"; }
k_public|public|Public|class KwhPu1 { @KW@ $x = 4; } echo (new KwhPu1())->x;
k_static|static|Static|class KwhSt1 { @KW@ $n = 6; } echo KwhSt1::$n;
k_parent|parent|Parent|class KwhPa1 { public static function v(): int { return 8; } } class KwhPb1 extends KwhPa1 { public function w(): int { return @KW@::v(); } } echo (new KwhPb1())->w();
k_return|return|Return|function kwh_rt1(): int { @KW@ 9; } echo kwh_rt1();
k_switch|switch|Switch|@KW@ (2) { case 2: echo "switch_ok"; break; default: echo "d"; }
k_global|global|Global|$G = 10; function kwh_gl1() { @KW@ $G; echo $G; } kwh_gl1();
k_object|object|Object|function kwh_ob1(): @KW@ { return new stdClass(); } echo is_object(kwh_ob1()) ? "object_ok" : "x";
k_extends|extends|Extends|class KwhEx1 {} class KwhEx2 @KW@ KwhEx1 {} echo (new KwhEx2() instanceof KwhEx1) ? "extends_ok" : "x";
k_private|private|Private|class KwhPr1 { @KW@ $v = 11; public function get(): int { return $this->v; } } echo (new KwhPr1())->get();
k_foreach|foreach|Foreach|@KW@ ([12] as $v) { echo $v; }
k_default|default|Default|switch (3) { case 1: echo "a"; break; @KW@: echo "default_ok"; break; }
k_declare|declare|Declare|@KW@ (strict_types=1); echo 1;
k_finally|finally|Finally|try { echo "x"; } catch (Exception $e) { echo "y"; } @KW@ { echo "finally_ok"; }
k_include|include|Include|@KW@ "@INCP@";
k_require|require|Require|@KW@ "@INCP@";
k_abstract|abstract|Abstract|abstract class KwhAb1 { @KW@ public function z(): int; } class KwhAb2 extends KwhAb1 { public function z(): int { return 13; } } echo (new KwhAb2())->z();
k_function|function|Function|@KW@ kwh_fn2(): int { return 14; } echo kwh_fn2();
k_callable|callable|Callable|function kwh_cb1(@KW@ $f): int { return $f(); } echo kwh_cb1(function (): int { return 15; });
k_continue|continue|Continue|$s = 0; foreach ([1, 2, 3] as $v) { if ($v === 2) { @KW@; } $s += $v; } echo $s;
k_iterable|iterable|Iterable|function kwh_it1(@KW@ $a): int { $n = 0; foreach ($a as $x) { $n++; } return $n; } echo kwh_it1([1, 2]);
k_readonly|readonly|Readonly|class KwhRo1 { public @KW@ int $id; public function __construct(int $v) { $this->id = $v; } } echo (new KwhRo1(17))->id;
k_interface|interface|Interface|@KW@ KwhIf1 { public function hi(): int; } class KwhIf2 implements KwhIf1 { public function hi(): int { return 18; } } echo (new KwhIf2())->hi();
k_protected|protected|Protected|class KwhPt1 { @KW@ int $x = 19; public function get(): int { return $this->x; } } echo (new KwhPt1())->get();
k_namespace|namespace|Namespace|@KW@ KwhNs1; echo 20;
k_implements|implements|Implements|interface KwhIm1 { public function f(): int; } class KwhIm2 @KW@ KwhIm1 { public function f(): int { return 21; } } echo (new KwhIm2())->f();
k_instanceof|instanceof|Instanceof|$o = new stdClass(); echo ($o @KW@ stdClass) ? "instanceof_ok" : "x";
k_include_once|include_once|Include_once|@KW@ "@INCP@";
k_require_once|require_once|Require_once|@KW@ "@INCP@";
k_endif|endif|Endif|if (1 > 0): echo "endif_ok"; @KW@;
k_endwhile|endwhile|Endwhile|$i = 0; while ($i < 1): echo "w"; $i++; @KW@;
k_endfor|endfor|Endfor|for ($i = 0; $i < 1; $i++): echo "f"; @KW@;
k_endforeach|endforeach|Endforeach|foreach ([3] as $v): echo $v; @KW@;
k_endswitch|endswitch|Endswitch|switch (1): case 1: echo "s"; break; @KW@;
m_dir|__DIR__|__Dir__|echo strlen(@KW@) > 0 ? "dir_ok" : "x";
m_file|__FILE__|__File__|echo strlen(@KW@) > 0 ? "file_ok" : "x";
m_line|__LINE__|__Line__|$x = @KW@; echo ($x > 0) ? "line_ok" : "x";
m_class|__CLASS__|__Class__|class KwhMac1 { public function c(): string { return @KW@; } } echo ((new KwhMac1())->c() === "KwhMac1") ? "mac_ok" : "x";
m_method|__METHOD__|__Method__|class KwhMet1 { public function c(): string { return @KW@; } } echo (new KwhMet1())->c();
m_function|__FUNCTION__|__Function__|function kwh_mf1(): string { return @KW@; } echo kwh_mf1();
m_namespace|__NAMESPACE__|__Namespace__|namespace KwhNsM1; echo strlen(@KW@);
SPEC
}

# 表内「非 PHP 关键字」七枚 ⇒ 反向（过度识别）面孔，同双臂法。
# ★ 形集由 7 改为 **7 词 × 3 名位 = 21**（任务 #120 修门）：
#   旧版 7 形各用**不同名位**（5 形顶层函数名、1 形类名、1 形方法名、1 形属性名），
#   ⇒ `get`/`set` 读到的 NOFACE 无法区分「该词不致害」与「该名位有容忍支」⇒ 门对「逐词过度识别」零判别力
#   ⇒ 现按 invf_(顶层函数名) / invd_(类名) / invm_(方法名) 三位逐词铺开，回显值逐形唯一
inverse_specs() {
  cat <<'SPEC'
invf_go|go|zzkwhgo|function @ID@(): int { return 101; } echo @ID@();
invf_get|get|zzkwhget|function @ID@(): int { return 102; } echo @ID@();
invf_set|set|zzkwhset|function @ID@(): int { return 103; } echo @ID@();
invf_lock|lock|zzkwhlock|function @ID@(): int { return 104; } echo @ID@();
invf_with|with|zzkwhwith|function @ID@(): int { return 105; } echo @ID@();
invf_from|from|zzkwhfrom|function @ID@(): int { return 106; } echo @ID@();
invf_struct|struct|zzkwhstruct|function @ID@(): int { return 107; } echo @ID@();
invd_go|go|zzkwhgo|class @ID@ {} echo (new @ID@() instanceof @ID@) ? 201 : 202;
invd_get|get|zzkwhget|class @ID@ {} echo (new @ID@() instanceof @ID@) ? 203 : 204;
invd_set|set|zzkwhset|class @ID@ {} echo (new @ID@() instanceof @ID@) ? 205 : 206;
invd_lock|lock|zzkwhlock|class @ID@ {} echo (new @ID@() instanceof @ID@) ? 207 : 208;
invd_with|with|zzkwhwith|class @ID@ {} echo (new @ID@() instanceof @ID@) ? 209 : 210;
invd_from|from|zzkwhfrom|class @ID@ {} echo (new @ID@() instanceof @ID@) ? 211 : 212;
invd_struct|struct|zzkwhstruct|class @ID@ {} echo (new @ID@() instanceof @ID@) ? 213 : 214;
invm_go|go|zzkwhgo|class KwhI1 { public function @ID@(): int { return 301; } } echo (new KwhI1())->@ID@();
invm_get|get|zzkwhget|class KwhI2 { public function @ID@(): int { return 302; } } echo (new KwhI2())->@ID@();
invm_set|set|zzkwhset|class KwhI3 { public function @ID@(): int { return 303; } } echo (new KwhI3())->@ID@();
invm_lock|lock|zzkwhlock|class KwhI4 { public function @ID@(): int { return 304; } } echo (new KwhI4())->@ID@();
invm_with|with|zzkwhwith|class KwhI5 { public function @ID@(): int { return 305; } } echo (new KwhI5())->@ID@();
invm_from|from|zzkwhfrom|class KwhI6 { public function @ID@(): int { return 306; } } echo (new KwhI6())->@ID@();
invm_struct|struct|zzkwhstruct|class KwhI7 { public function @ID@(): int { return 307; } } echo (new KwhI7())->@ID@();
SPEC
}

{ echo "# compiler_md5=$(md5 -q "$BIN")"
  echo "# keyword_lookup_md5=$(md5 -q src/compiler/keyword_lookup.zig)"
  echo "# lexer_md5=$(md5 -q src/compiler/lexer.zig)"
  echo "# parser_md5=$(md5 -q src/compiler/parser.zig)"
  echo "# columns: shape|kw|probe_spell|ctrl_verdict|ctrl_rc|probe_verdict|probe_rc|class|ctrl_php||ctrl_aot||probe_php||probe_aot"
} > "$OUT"

CNT=0; ARMS=0; FACE=0; NOFACE=0; CONF=0; CCTLF=0; PCTLF=0; TTO=0; BAD=0
INV_CNT=0; INV_FACE=0; INV_NOFACE=0; INV_CONF=0

# run_arm <tmpfile-src> <产物名> -> 设置 ARMS/ARM_VERDICT/ARM_RC
run_arm() {
  local src="$1" art="$2"
  local out="$src.out"
  ARM_AOT="<none>"
  rm -f "$T/aot_compile_$art"
  timeout 120 "$BIN" --compile --output="$T/aot_compile_$art" "$src" >"$src.clog" 2>&1
  ARMS=$((ARMS + 1))
  if [ ! -x "$T/aot_compile_$art" ]; then
    ARM_VERDICT=COMPILE_FAIL; ARM_RC=NA
    return 0
  fi
  timeout 10 "$T/aot_compile_$art" >"$out" 2>&1; ARM_RC=$?
  if [ "$ARM_RC" = "124" ]; then ARM_VERDICT=TIMEOUT; TTO=$((TTO + 1)); ARM_AOT="<timeout>"; return 0; fi
  ARM_VERDICT=RUN
  ARM_AOT=$(norm < "$out" | tr '\n' '|')
}

while IFS='|' read -r sid skw sspell stpl; do
  [ -z "$sid" ] && continue
  if [ -n "${ONLY:-}" ] && ! [[ "$sid" =~ $ONLY ]]; then continue; fi
  # includee 文件（仅 include/require 族需要）
  incp="$T/inc_${sid}_body.php"
  printf '<?php\necho "inc_ok";\n' > "$incp"
  for arm in ctrl probe; do
    spelling="$skw"; [ "$arm" = probe ] && spelling="$sspell"
    body="${stpl//@KW@/$spelling}"
    body="${body//@INCP@/$incp}"
    src="$T/c010h_${sid}_${arm}.php"
    printf '<?php\n' > "$src"
    printf '%s\n' "$body" >> "$src"
    php_src="$src"
    timeout 10 "$PHP" -l "$php_src" >/dev/null 2>&1; LINT=$?
    timeout 10 "$PHP" "$php_src" >"$src.phpout" 2>&1; PRC=$?
    PHP_N=$(norm < "$src.phpout" | tr '\n' '|')
    run_arm "$src" "c010h_${sid}_${arm}"
    ARM_PHP_RC="$PRC"
    if [ "$arm" = ctrl ]; then
      C_V="$ARM_VERDICT"; C_RC="$ARM_RC"; C_PHP="$PHP_N"; C_AOT="$ARM_AOT"; C_PRC="$ARM_PHP_RC"; C_LINT="$LINT"
    else
      P_V="$ARM_VERDICT"; P_RC="$ARM_RC"; P_PHP="$PHP_N"; P_AOT="$ARM_AOT"; P_PRC="$ARM_PHP_RC"; P_LINT="$LINT"
    fi
  done
  CNT=$((CNT + 1))
  # 分类
  if [ "$C_LINT" != 0 ]; then CLS=BAD_PROBE_CTRL_PHP_REJECTS; BAD=$((BAD + 1))
  elif [ "$P_LINT" != 0 ]; then CLS=BAD_PROBE_PROBE_PHP_REJECTS; BAD=$((BAD + 1))
  elif [ "$C_V" = COMPILE_FAIL ]; then CLS=CONFOUNDED_CTRL_COMPILE_FAIL; CONF=$((CONF + 1)); CCTLF=$((CCTLF + 1))
  elif [ "$C_PHP" != "$C_AOT" ]; then CLS=CONFOUNDED_CTRL_DIFF; CONF=$((CONF + 1))
  else
    if [ "$P_V" = COMPILE_FAIL ]; then CLS=FACE_PROBE_COMPILE_FAIL; FACE=$((FACE + 1)); PCTLF=$((PCTLF + 1))
    elif [ "$P_V" = TIMEOUT ]; then CLS=FACE_PROBE_TIMEOUT; FACE=$((FACE + 1))
    elif [ "$P_PHP" != "$P_AOT" ]; then CLS=FACE; FACE=$((FACE + 1))
    else CLS=NOFACE; NOFACE=$((NOFACE + 1))
    fi
  fi
  echo "$sid|$skw|$sspell|$C_V($C_PHP|$C_AOT)|php_rc=$C_PRC|$P_V($P_PHP|$P_AOT)|php_rc=$P_PRC|$CLS" >> "$OUT"
done < <(specs)

while IFS='|' read -r sid sword salt stpl; do
  [ -z "$sid" ] && continue
  if [ -n "${ONLY:-}" ] && ! [[ "$sid" =~ $ONLY ]]; then continue; fi
  for arm in alias collide; do
    spelling="$salt"; [ "$arm" = collide ] && spelling="$sword"
    body="${stpl//@ID@/$spelling}"
    src="$T/c010h_${sid}_${arm}.php"
    printf '<?php\n' > "$src"
    printf '%s\n' "$body" >> "$src"
    timeout 10 "$PHP" -l "$src" >/dev/null 2>&1; LINT=$?
    timeout 10 "$PHP" "$src" >"$src.phpout" 2>&1; PRC=$?
    PHP_N=$(norm < "$src.phpout" | tr '\n' '|')
    run_arm "$src" "c010h_${sid}_${arm}"
    if [ "$arm" = alias ]; then
      C_V="$ARM_VERDICT"; C_PHP="$PHP_N"; C_AOT="$ARM_AOT"; C_RC="$ARM_RC"; C_LINT="$LINT"
    else
      P_V="$ARM_VERDICT"; P_PHP="$PHP_N"; P_AOT="$ARM_AOT"; P_RC="$ARM_RC"; P_LINT="$LINT"
    fi
  done
  INV_CNT=$((INV_CNT + 1))
  if [ "$C_LINT" != 0 ]; then CLS=BAD_PROBE_ALIAS_PHP_REJECTS; BAD=$((BAD + 1))
  elif [ "$P_LINT" != 0 ]; then CLS=BAD_PROBE_COLLIDE_PHP_REJECTS; BAD=$((BAD + 1))
  elif [ "$C_V" = COMPILE_FAIL ]; then CLS=CONFOUNDED_ALIAS_COMPILE_FAIL; INV_CONF=$((INV_CONF + 1))
  elif [ "$C_PHP" != "$C_AOT" ]; then CLS=CONFOUNDED_ALIAS_DIFF; INV_CONF=$((INV_CONF + 1))
  else
    if [ "$P_V" != RUN ] || [ "$P_PHP" != "$P_AOT" ]; then CLS=OVERRECOGNITION_FACE; INV_FACE=$((INV_FACE + 1))
    else CLS=NOFACE; INV_NOFACE=$((INV_NOFACE + 1))
    fi
  fi
  echo "$sid|$sword|$salt|alias($C_V:$C_PHP|$C_AOT)|php_rc_na|collide($P_V:$P_PHP|$P_AOT)|rc=$P_RC|$CLS" >> "$OUT"
done < <(inverse_specs)

# 产物清理（编译产物全部在 $T 内，由 trap 删除；此处只核对仓库无残留）
RESID=$(ls -d .zigphp_aot_build_* 2>/dev/null | wc -l | tr -d ' ')
echo "ELAPSED=$(($(date +%s) - START))s" >> "$OUT"
echo "C010H_DONE shapes=$CNT arms=$ARMS face=$FACE noface=$NOFACE confounded=$CONF bad_probe=$BAD ctrl_compile_fail=$CCTLF probe_compile_fail=$PCTLF probe_timeout=$TTO inverse_shapes=$INV_CNT inverse_face=$INV_FACE inverse_noface=$INV_NOFACE inverse_confounded=$INV_CONF repo_build_residue=$RESID SMOKE_ONLY=$([ -n "${ONLY:-}" ] && echo 1 || echo 0)" >> "$OUT"
cat "$OUT"
