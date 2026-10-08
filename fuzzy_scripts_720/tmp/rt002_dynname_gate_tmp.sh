#!/usr/bin/env bash
# 永久侧门 D（任务 #117 → 工单 AOT-RUNTIME-002 §3 G4-f / §7-8，2026-10-07）：
#   动态类名限定静态属性时，`::` 左侧的类名操作数究竟被解析成什么
#
# 本门要回答的唯一问题：
#   `$cls::$v` / `$o::$v` / `($cls)::$v` 三种「非字面类名」限定形，在 AOT 里
#   (a) 读/写各自的运行结局（PHP 真值 vs AOT），
#   (b) 生成码里传给模板入口的 class_name **实参字面量**是什么
#
# 首跑 9 形已定案（勿再按开轮前的假设判读）：
#   读数 `DYNNAME_DONE shapes=9 same=4 diff=5 cnotfound_fatal=5 compile_fail=0`（`ELAPSED=34s`）
#     SAME  = dyn_read_lit / dyn_read_str / dyn_read_paren / dyn_write_lit
#     DIFF  = dyn_read_obj / dyn_write_str / dyn_write_obj / dyn_write_paren / dyn_ref_source
#             （五形 AOT 一律 `error: ClassNotFound` rc=1，PHP 侧 rc=0 且写入/回读均正确）
#   ✗ 否证「parser 把变量名当类名」这一开轮前候选：`parser.zig:2537-2557` 的 `.variable` 分支**不是**病根
#     —— 生成码首实参保留了原始 token 文本（**含 `$`**），且字符串形读侧实测 SAME
#     ⇒ parser 交出的东西是可判别的，读侧正是靠它工作。
#   ✓ 成因一（**IR 站点缺 `$` 分支**，共 7 处）：
#     读侧 `ir_generator.zig:8443` 的 `generateStaticPropertyAccess` 显式判 `class_name[0] == '$'`
#     ⇒ 取变量值并改走 `php_get_static_property_dynamic`（`:20198`）；
#     而 6 处 `.static_property_set` 写站点（`:4379`/`:4749`/`:4922`/`:5361`/`:5915`/`:6051`）
#     与引用赋值**源**侧站点（`:4547-4556`，实测 emit = `php_get_static_property("$cls", "v")`）
#     只归一 `self`/`static`，把 `"$cls"`/`"$o"` 原样当字面类名交出
#     ⇒ 模板 `findClass("$cls")` 落空（写 `:20380`／读 `:20334`）⇒ 运行致命 `ClassNotFound` rc=1。
#   ✓ 成因二（**模板动态读入口不接受对象**，独立第二条环）：
#     `php_get_static_property_dynamic:20200` = `if (args[0].isString()) … else ""`
#     ⇒ `dyn_read_obj` 的 emit **已**正确走到该 helper，却因对象 → 空类名而致命
#     ⇒ 与 AOT-CODEGEN-009 的 `php_get_class_constant_dynamic:20210` `else ""` **同一模式**。
#   ⇒ 括号形 `($cls)::$v = 9` 实测与裸变量写形生成码同形（parens 对 parser 透明），
#     但读侧括号形实测 SAME ⇒ 「parens 在写侧只是同一枚 `.static_property_access` 节点」。
#   ⇒ 修复面 = **三处同动**，缺一无效：
#     ① 新增写侧模板入口（对称于 `:20198`，须同时接受字符串与对象 → `class_meta.name`）；
#     ② 7 处 IR 站点补 `$` 前缀分支（6 写 + 1 引用源）；
#     ③ 读侧动态入口 `:20200` 的对象支补上（否则 `dyn_read_obj` 仍红）。
#
# 判读口径：
#   1) 等值 = 归一化合并 stdout+stderr 逐字节；exit 码只记录不判等
#   2) 额外单列 emit = 生成码中 `php_get_static_property(`/`php_set_static_property(`/
#      `php_get_static_property_dynamic(`/`php_set_static_property_dynamic(` 的调用行（含首实参）
#      ⇒ 实测：写侧出现 `php_set_static_property("$cls", "v", reg_1)` 即证实「变量文本被当类名」；
#         读侧出现 `php_get_static_property_dynamic(...)` 即证实该形**已**走动态入口（此后仍红 ⇒ 病在模板）
#   3) 控制臂**两枚**：`dyn_read_lit`（字面类名读）与 `dyn_write_lit`（字面类名写）**必须始终 SAME**
#      ⇒ 二者锁定「读/写通道本身可用」，故五枚红形不可归因于门坏掉
#   4) 静态属性一律**不带类型**（`public static $v = 5;`）⇒ 把 G4-f 与 G4-a（零 coerce）/
#      G4-b（未初始化无表示）隔离开，本门只测「类名操作数解析」这一面
#   5) 每形独立编译、纯直线语句、无 if/elseif 链（CODEGEN-008 零发射面）；每形专属类名（静态属性为进程级全局）
#   6) 产物名 aot_compile_*，且不落在源目录；KEEP_TEMP 目录本门自取自删
set -u
cd "$(dirname "$0")/../.." || exit 1
BIN="zig-out/bin/php-interpreter"
PHP="/opt/homebrew/bin/php"
OUT="fuzzy_scripts_720/tmp/rt002_dynname_tmp.tsv"
T=$(mktemp -d /tmp/rt002dyn.XXXXXX)
trap 'rm -rf "$T"' EXIT
START=$(date +%s)

norm() { sed -E -e 's/[[:space:]]*$//' -e 's|/[^[:space:]:]*\.php:[0-9]+|FILE:LINE|g' -e 's| in [^ ]*\.php on line [0-9]+| in FILE:LINE|g' -e '/^Stack trace:/,$d' -e '/^$/d'; }

cat > "$T/prelude.php" <<'PRELUDE'
<?php
class DynA { public static $v = 5; }
class DynB { public static $v = 5; }
class DynC { public static $v = 5; }
class DynD { public static $v = 5; }
class DynE { public static $v = 5; }
class DynF { public static $v = 5; }
class DynG { public static $v = 5; }
class DynH { public static $v = 5; }
class DynI { public static $v = 5; }
PRELUDE

body_for() {
  case "$1" in
    dyn_read_lit)  printf '%s\n' 'echo "read=" . var_export(DynA::$v, true) . "\n";' ;;
    dyn_read_str)  printf '%s\n' '$cls = "DynB";' 'echo "read=" . var_export($cls::$v, true) . "\n";' ;;
    dyn_write_str) printf '%s\n' '$cls = "DynC";' '$cls::$v = 9;' 'echo "via_lit=" . var_export(DynC::$v, true) . "\n";' ;;
    dyn_write_obj) printf '%s\n' '$o = new DynD();' '$o::$v = 9;' 'echo "via_lit=" . var_export(DynD::$v, true) . "\n";' ;;
    dyn_write_paren) printf '%s\n' '$cls = "DynE";' '($cls)::$v = 9;' 'echo "via_lit=" . var_export(DynE::$v, true) . "\n";' ;;
    dyn_read_paren) printf '%s\n' '$cls = "DynG";' 'echo "read=" . var_export(($cls)::$v, true) . "\n";' ;;
    dyn_read_obj) printf '%s\n' '$o = new DynH();' 'echo "read=" . var_export($o::$v, true) . "\n";' ;;
    dyn_ref_source) printf '%s\n' '$cls = "DynF";' '$r = &$cls::$v;' 'echo "ref=" . var_export($r, true) . "\n";' '$r = 3;' 'echo "via_lit=" . var_export(DynF::$v, true) . "\n";' ;;
    dyn_write_lit) printf '%s\n' 'DynI::$v = 9;' 'echo "via_lit=" . var_export(DynI::$v, true) . "\n";' ;;
    *) printf '' ;;
  esac
}

{ echo "# compiler_md5=$(md5 -q "$BIN")"
  echo "# runtime_lib_template_md5=$(md5 -q src/aot/runtime_lib_template.zig)"
  echo "# ir_generator_md5=$(md5 -q src/aot/ir_generator.zig)"
  echo "# parser_md5=$(md5 -q src/compiler/parser.zig)"
  echo "# prelude_md5=$(md5 -q "$T/prelude.php")"
  echo "# columns: shape|php_rc|aot_rc|verdict||php_norm||aot_norm||emit"
} > "$OUT"

COUNT=0; SAME_N=0; DIFF_N=0; CF_N=0; FATAL_N=0
for s in dyn_read_lit dyn_read_str dyn_read_paren dyn_read_obj dyn_write_lit dyn_write_str dyn_write_obj dyn_write_paren dyn_ref_source; do
  COUNT=$((COUNT + 1))
  SRC="$T/dyn_${s}_tmp.php"
  cp "$T/prelude.php" "$SRC"
  body_for "$s" >> "$SRC"
  echo 'echo "DONE\n";' >> "$SRC"

  # 记录编译前的 KEEP_TEMP 目录集合，便于取本次新增者
  BEFORE=$(ls -d .zigphp_aot_build_* 2>/dev/null | tr '\n' ' ')
  if ! timeout 120 env ZIGPHP_AOT_KEEP_TEMP=1 "$BIN" --compile --output="$T/aot_compile_dyn_${s}_tmp" "$SRC" >"$T/$s.compile.log" 2>&1; then
    echo "$s|php_rc=NA|aot_rc=NA|COMPILE_FAIL|- $(tail -3 "$T/$s.compile.log" | tr '\n' '|')||" >> "$OUT"
    CF_N=$((CF_N + 1))
    for d in $(ls -d .zigphp_aot_build_* 2>/dev/null | tr '\n' ' '); do
      case " $BEFORE " in *" $d "*) ;; *) [ -n "$d" ] && rm -rf "$d" ;; esac
    done
    continue
  fi

  # 本次生成码里的静态属性入口调用行（首实参 = class_name）
  GEN=""
  for d in $(ls -d .zigphp_aot_build_* 2>/dev/null | tr '\n' ' '); do
    case " $BEFORE " in *" $d "*) continue ;; esac
    [ -z "$d" ] && continue
    if [ -f "$d/main.zig" ]; then GEN="$d/main.zig"; break; fi
  done
  EMIT="none"
  if [ -n "$GEN" ]; then
    EMIT=$(grep -oE 'php_(get|set)_static_property(_dynamic)?\([^;]{0,80}' "$GEN" | head -4 | tr '|' '/')
    [ -z "$EMIT" ] && EMIT="no_call"
  fi
  # 立即清理本次 KEEP_TEMP 目录（§三-7）
  for d in $(ls -d .zigphp_aot_build_* 2>/dev/null | tr '\n' ' '); do
    case " $BEFORE " in *" $d "*) ;; *) [ -n "$d" ] && rm -rf "$d" ;; esac
  done

  timeout 10 "$PHP" "$SRC" >"$T/$s.php.out" 2>&1; prc=$?
  timeout 10 "$T/aot_compile_dyn_${s}_tmp" >"$T/$s.aot.out" 2>&1; arc=$?
  php_n=$(norm < "$T/$s.php.out" | tr '\n' '|')
  aot_n=$(norm < "$T/$s.aot.out" | tr '\n' '|')
  if [ "$php_n" = "$aot_n" ]; then v=SAME; SAME_N=$((SAME_N + 1)); else v=DIFF; DIFF_N=$((DIFF_N + 1)); fi
  if grep -q 'ClassNotFound' "$T/$s.aot.out"; then FATAL_N=$((FATAL_N + 1)); fi
  echo "$s|php_rc=$prc|aot_rc=$arc|$v|$php_n||aot=$aot_n||emit=$EMIT" >> "$OUT"
done

echo "ELAPSED=$(($(date +%s) - START))s" >> "$OUT"
echo "DYNNAME_DONE shapes=$COUNT same=$SAME_N diff=$DIFF_N cnotfound_fatal=$FATAL_N compile_fail=$CF_N" >> "$OUT"
cat "$OUT"
