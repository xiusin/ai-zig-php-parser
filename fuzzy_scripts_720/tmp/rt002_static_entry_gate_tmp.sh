#!/usr/bin/env bash
# 永久侧门 C（任务 #116 → 工单 AOT-RUNTIME-002 §7 第 2 项，2026-10-07）：静态属性入口族
#
# 为什么是第四张门（口径，勿删）：
#   主门 rt002_isolation_gate_tmp.sh（total=12）、侧门 A rt002_g3_probe_run_tmp.sh（total=5）、
#   侧门 B rt002_g3_uninit_probe_run_tmp.sh（total=2）的 shapes= 读数都已写进工单 §6/§7 ⇒
#   按流程教训「已引用 total= 的门禁止回头加形」，本门单独成文件、单独成 token。
#
# 本门要回答的唯一问题：
#   实例侧三组偏差（G1 消息类名 / G2 越权 private / G3 强转失败后槽污染）在**静态属性入口**
#   （php_get_static_property / php_set_static_property）上是否同形？
#   源码侧只读预研（任务 #116）给出的可证伪预期：
#     - php_set_static_property:20361-20395 从不调用 coercePropertyType，直接落到
#       ClassMeta.setStaticProperty:17806-17812（零类型、零 readonly 守卫）
#       ⇒ 预期「静态 typed 属性写错类型 = AOT 静默接受」，与 G3 是**不同机制**（G3 是异常对象进槽，本形是根本不校验）
#     - 发射侧 native_linker.zig:24262（读）/:24303（写）都在调用后立刻 hasException() 路由，
#       写侧返回值被 `_ =` 丢弃 ⇒ 预期 G3 的「异常对象进寄存器」污染在静态侧**不成立**
#     - :20342/:20388 的 access 消息用 decl.class.name，而 PHP 8.5 实测：
#       越权 access 消息名**called class**、类型消息名**declaring class**
#       ⇒ 预期子类名访问父类 private 静态属性时 AOT 消息类名错（与实例侧「用实例类」规律同向）
#     - `st_child_write_alias` 隔离「静态存储按类名分槽」这一独立机制：PHP 中静态属性归属**声明类**，
#       以子类名写入等于写父类槽；若 AOT 把值放进子类自己的 map，则父类名回读读不到 ⇒ 与类型校验缺失无关
#   控制臂：仅 `st_ok_write`（合法写，必须始终 SAME），用来证明本门的读写通道与消息本身可用，
#   差异不是门自身坏掉。
#   首跑已纠正的头部预期（勿按旧措辞判读）：`st_priv_read`（以声明类自身类名越权读 private 静态属性）
#   **不是控制臂**，实测为 DIFF —— PHP 报 `Error: Cannot access private property STPriv::$p`，
#   AOT 静默返回 `p=1` ⇒ 该形属 G4-c（可见性 fail-open，成因在发射侧 `ClassContext.init(m, m)`），
#   判读时须与 `st_priv_write`/`st_inherit_priv_read` 同组看，不可当作门基线。
#   固化到门的事实：PHP 8.5 实测 `readonly` **不可**用于静态属性
#   （`Static property X::$y cannot be readonly`）⇒ 本门不含 readonly 静态形，勿再补。
#
# 固化坑：
#   1) 每形独立编译，纯直线语句，无 if/elseif 链（受 AOT-CODEGEN-008 零发射面污染的形状不进本门）
#   2) 静态属性是**进程级全局**，同一文件内多形共用会串味 ⇒ 每形一枚专属类名（含父/子对）
#   3) 等值判据 = 归一化后 stdout+stderr 合并逐字节；exit 码只记录不判等
#   4) 产物名 aot_compile_*，且不落在源目录
set -u
cd "$(dirname "$0")/../.." || exit 1
BIN="zig-out/bin/php-interpreter"
PHP="/opt/homebrew/bin/php"
OUT="fuzzy_scripts_720/tmp/rt002_static_entry_tmp.tsv"
T=$(mktemp -d /tmp/rt002st.XXXXXX)
trap 'rm -rf "$T"' EXIT
START=$(date +%s)

norm() { sed -E -e 's/[[:space:]]*$//' -e 's|/[^[:space:]:]*\.php:[0-9]+|FILE:LINE|g' -e 's| in [^ ]*\.php on line [0-9]+| in FILE:LINE|g' -e '/^Stack trace:/,$d' -e '/^$/d'; }

cat > "$T/prelude.php" <<'PRELUDE'
<?php
class STOk { public static int $v; }
class STBad { public static int $v; }
class STCoerce { public static int $v; }
class STUn { public static string $s; }
class STPriv { private static int $p = 1; }
class STPrivW { private static int $p = 1; }
class STPa { private static int $p = 1; }
class STPaC extends STPa {}
class STTb { public static int $v; }
class STTbC extends STTb {}
class STAl { public static int $v; }
class STAlC extends STAl {}

$show = static function (callable $f): void {
    try {
        $f();
        echo "NO_ERROR\n";
    } catch (Throwable $e) {
        echo get_class($e) . ": " . $e->getMessage() . "\n";
    }
};
PRELUDE

body_for() {
  case "$1" in
    st_ok_write) printf '%s\n' \
      '$show(static function (): void { STOk::$v = 3; });' \
      '$show(static function (): void { echo "t=" . gettype(STOk::$v) . " v=" . var_export(STOk::$v, true) . "\n"; });' ;;
    st_type_bad) printf '%s\n' \
      '$show(static function (): void { STBad::$v = "abc"; });' \
      '$show(static function (): void { echo "t=" . gettype(STBad::$v) . " v=" . var_export(STBad::$v, true) . "\n"; });' ;;
    st_type_coerce) printf '%s\n' \
      '$show(static function (): void { STCoerce::$v = "42"; });' \
      '$show(static function (): void { echo "t=" . gettype(STCoerce::$v) . " v=" . var_export(STCoerce::$v, true) . "\n"; });' ;;
    st_uninit_read) printf '%s\n' \
      '$show(static function (): void { echo "read=" . var_export(STUn::$s, true) . "\n"; });' ;;
    st_priv_read) printf '%s\n' \
      '$show(static function (): void { echo "p=" . var_export(STPriv::$p, true) . "\n"; });' ;;
    st_priv_write) printf '%s\n' \
      '$show(static function (): void { STPrivW::$p = 5; });' \
      '$show(static function (): void { echo "p=" . var_export(STPrivW::$p, true) . "\n"; });' ;;
    st_inherit_priv_read) printf '%s\n' \
      '$show(static function (): void { echo "cp=" . var_export(STPaC::$p, true) . "\n"; });' ;;
    st_inherit_type_bad) printf '%s\n' \
      '$show(static function (): void { STTbC::$v = "abc"; });' \
      '$show(static function (): void { echo "t=" . gettype(STTb::$v) . " v=" . var_export(STTb::$v, true) . "\n"; });' ;;
    st_child_write_alias) printf '%s\n' \
      '$show(static function (): void { STAlC::$v = 8; });' \
      '$show(static function (): void { echo "via_parent=" . gettype(STAl::$v) . "/" . var_export(STAl::$v, true) . " via_child=" . gettype(STAlC::$v) . "/" . var_export(STAlC::$v, true) . "\n"; });' ;;
    *) printf '' ;;
  esac
}

{ echo "# compiler_md5=$(md5 -q "$BIN")"
  echo "# runtime_lib_template_md5=$(md5 -q src/aot/runtime_lib_template.zig)"
  echo "# ir_generator_md5=$(md5 -q src/aot/ir_generator.zig)"
  echo "# prelude_md5=$(md5 -q "$T/prelude.php")"
  echo "# columns: shape|php_rc|aot_rc|verdict|acc(php/aot)|te(php/aot)|bi(php/aot)|accname(php/aot)||php_norm||aot_norm"
} > "$OUT"

flag() { if grep -q "$2" "$1"; then echo YES; else echo NO; fi; }
accname() { grep -o 'Cannot access private property [A-Za-z0-9_]*' "$1" 2>/dev/null | head -1 | awk '{print $5}'; }

COUNT=0; SAME_N=0; DIFF_N=0; CF_N=0; LOST_N=0
for s in st_ok_write st_type_bad st_type_coerce st_uninit_read st_priv_read st_priv_write st_inherit_priv_read st_inherit_type_bad st_child_write_alias; do
  COUNT=$((COUNT + 1))
  SRC="$T/st_${s}_tmp.php"
  cp "$T/prelude.php" "$SRC"
  body_for "$s" >> "$SRC"
  echo 'echo "DONE\n";' >> "$SRC"

  if ! timeout 120 "$BIN" --compile --output="$T/aot_compile_st_${s}_tmp" "$SRC" >"$T/$s.compile.log" 2>&1; then
    echo "$s|php_rc=NA|aot_rc=NA|COMPILE_FAIL|-|-|-|- $(tail -3 "$T/$s.compile.log" | tr '\n' '|')" >> "$OUT"
    CF_N=$((CF_N + 1))
    continue
  fi

  timeout 10 "$PHP" "$SRC" >"$T/$s.php.out" 2>&1; prc=$?
  timeout 10 "$T/aot_compile_st_${s}_tmp" >"$T/$s.aot.out" 2>&1; arc=$?
  php_n=$(norm < "$T/$s.php.out" | tr '\n' '|')
  aot_n=$(norm < "$T/$s.aot.out" | tr '\n' '|')
  if [ "$php_n" = "$aot_n" ]; then v=SAME; SAME_N=$((SAME_N + 1)); else v=DIFF; DIFF_N=$((DIFF_N + 1)); fi

  pa=$(flag "$T/$s.php.out" 'Cannot access private property'); aa=$(flag "$T/$s.aot.out" 'Cannot access private property')
  pt=$(flag "$T/$s.php.out" 'TypeError'); at=$(flag "$T/$s.aot.out" 'TypeError')
  pb=$(flag "$T/$s.php.out" 'must not be accessed before initialization'); ab=$(flag "$T/$s.aot.out" 'must not be accessed before initialization')
  pnm=$(accname "$T/$s.php.out"); anm=$(accname "$T/$s.aot.out")
  if { [ "$pa" = YES ] || [ "$pt" = YES ] || [ "$pb" = YES ]; } && [ "$aa" = NO ] && [ "$at" = NO ] && [ "$ab" = NO ]; then
    LOST_N=$((LOST_N + 1))
  fi
  echo "$s|php_rc=$prc|aot_rc=$arc|$v|acc(php=$pa/aot=$aa)|te(php=$pt/aot=$at)|bi(php=$pb/aot=$ab)|accname(php=$pnm/aot=$anm)|$php_n||aot=$aot_n" >> "$OUT"
done

echo "ELAPSED=$(($(date +%s) - START))s" >> "$OUT"
echo "STATENTRY_DONE shapes=$COUNT same=$SAME_N diff=$DIFF_N protect_lost=$LOST_N compile_fail=$CF_N" >> "$OUT"
cat "$OUT"
