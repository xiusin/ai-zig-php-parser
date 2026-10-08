#!/usr/bin/env bash
# 永久门（任务 #114 → 工单 AOT-RUNTIME-002，2026-10-07）：属性写入入口语义「隔离门」
#
# 为什么需要这一张门（口径，勿删）：
#   f004_ro_unser_tmp.php 的 12 形靠 `$argv[1]` + if/elseif 链派发。生成码侧实测（KEEP_TEMP main.zig 逐行
#   setSourceLocation 计数）表明该链的第 5/6/7 臂条件（源 :220/:222/:224）发射指令数 = 0，链后语句
#   （源 :232/:234）整段发射数 = 0 ⇒ 该族的「AOT 缺 DONE / 缺 $show 输出」属 AOT-CODEGEN-008 的发射丢失，
#   不能算进属性入口语义的偏差。本门把每一形拆成「一个独立 PHP 文件 + 纯直线语句（无任何 if/elseif 链）」，
#   使 CODEGEN-008 无法介入，只剩「属性入口语义 + 异常消息归属」这一维。
#
# 固化坑：
#   1) 每形独立编译（argv 派发链会吃掉自己的臂 ⇒ 见 AOT-CODEGEN-008 §2）
#   2) 等值判据 = 归一化后 stdout+stderr 合并逐字节；exit 码只记录不判等（fatal 形两侧 255）
#   3) 错误消息里的「声明类 vs 实例类」差异属消息文本面，不被 §七-5（栈行号/路径豁免）覆盖，单列 msg_class_diff
#   4) 产物名 aot_compile_*，且不落在源目录
set -u
cd "$(dirname "$0")/../.." || exit 1
BIN="zig-out/bin/php-interpreter"
PHP="/opt/homebrew/bin/php"
OUT="fuzzy_scripts_720/tmp/runtime002_isolation_tmp.tsv"
T=$(mktemp -d /tmp/rt002.XXXXXX)
trap 'rm -rf "$T"' EXIT
START=$(date +%s)

norm() { sed -E -e 's/[[:space:]]*$//' -e 's|/[^[:space:]:]*\.php:[0-9]+|FILE:LINE|g' -e 's| in [^ ]*\.php on line [0-9]+| in FILE:LINE|g' -e '/^Stack trace:/,$d' -e '/^$/d'; }

cat > "$T/prelude.php" <<'PRELUDE'
<?php
class BBase {
    protected array $meta = [];

    public function __construct(public readonly string $uuid) {
    }

    public function __unserialize(array $data): void {
        $this->uuid = $data['uuid'];
    }

    final public function getUuid(): string {
        return $this->uuid;
    }
}

class BUser extends BBase {
    public function __unserialize(array $data): void {
        parent::__unserialize($data);
    }
}

class MBase {
    private string $secret = 'S';
    protected int $limit = 1;
    public int $total = 0;

    public function __construct(public readonly string $uuid) {
    }
}

class MChild extends MBase {
    public int $count = 0;

    public function scopeNames(): string {
        return 'self=' . self::class . ' static=' . static::class . ' parent=' . parent::class;
    }
}

$show = static function (callable $f): void {
    try {
        $f();
        echo "NO_ERROR\n";
    } catch (Throwable $e) {
        echo get_class($e) . ": " . $e->getMessage() . "\n";
    }
};
$c = new MChild("U001");
echo "obj=" . get_class($c) . " uuid=" . $c->uuid . "\n";
PRELUDE

body_for() {
  case "$1" in
    priv_read)   printf '%s\n' '$show(static function () use ($c): void { $x = $c->secret; echo isset($x) ? "read=$x" : "read=null"; });' ;;
    priv_write)  printf '%s\n' '$show(static function () use ($c): void { $c->secret = "X"; });' ;;
    prot_read)   printf '%s\n' '$show(static function () use ($c): void { $x = $c->limit; echo isset($x) ? "read=$x" : "read=null"; });' ;;
    type_inherit) printf '%s\n' '$show(static function () use ($c): void { $c->total = "str"; });' ;;
    type_self)   printf '%s\n' '$show(static function () use ($c): void { $c->count = "str"; });' ;;
    dyn_ro)      printf '%s\n' '$show(static function () use ($c): void { $k = "uuid"; $c->$k = "X2"; });' ;;
    class_const) printf '%s\n' 'echo "lit=" . MChild::class . "\n";' 'echo "var=" . $c::class . "\n";' 'echo "scope=" . $c->scopeNames() . "\n";' ;;
    val_self)    printf '%s\n' '$show(static function () use ($c): void { $c->count = "str"; });' 'echo "slot=" . var_export($c->count, true) . " type=" . gettype($c->count) . "\n";' ;;
    val_dyn)     printf '%s\n' '$show(static function () use ($c): void { $k = "uuid"; $c->$k = "X2"; });' 'echo "slot=" . var_export($c->uuid, true) . " type=" . gettype($c->uuid) . "\n";' ;;
    val_tinherit) printf '%s\n' '$show(static function () use ($c): void { $c->total = "str"; });' 'echo "slot=" . var_export($c->total, true) . " type=" . gettype($c->total) . "\n";' ;;
    fatal_ro)    printf '%s\n' '$b = new BUser("U001");' 'echo "constructed=" . $b->getUuid() . "\n";' '$b->__unserialize(["uuid" => "U002"]);' 'echo "unreached=" . $b->getUuid() . "\n";' ;;
    ro_write_same_scope) printf '%s\n' 'echo "before=" . $c->uuid . "\n";' '$show(static function () use ($c): void { $c->limit = 9; });' 'echo "after=" . $c->limit . "\n";' ;;
  esac
}

{ echo "# compiler_md5=$(md5 -q "$BIN")"
  echo "# native_linker_md5=$(md5 -q src/aot/native_linker.zig)"
  echo "# runtime_lib_template_md5=$(md5 -q src/aot/runtime_lib_template.zig)"
  echo "# prelude_md5=$(md5 -q "$T/prelude.php")"
  echo "# columns: shape|php_rc|aot_rc|verdict|msg_class_diff|php_norm||aot_norm"
} > "$OUT"

COUNT=0; SAME_N=0; DIFF_N=0; CF_N=0
for s in priv_read priv_write prot_read type_inherit type_self dyn_ro class_const val_self val_dyn val_tinherit fatal_ro ro_write_same_scope; do
  COUNT=$((COUNT + 1))
  SRC="$T/rt2_${s}_tmp.php"
  cp "$T/prelude.php" "$SRC"
  body_for "$s" >> "$SRC"
  echo 'echo "DONE\n";' >> "$SRC"

  if ! timeout 120 "$BIN" --compile --output="$T/aot_compile_rt2_${s}_tmp" "$SRC" >"$T/$s.compile.log" 2>&1; then
    echo "$s|php_rc=NA|aot_rc=NA|COMPILE_FAIL|msg_class_diff=NA|-||- $(tail -3 "$T/$s.compile.log" | tr '\n' '|')" >> "$OUT"
    CF_N=$((CF_N + 1))
    continue
  fi

  timeout 10 "$PHP" "$SRC" >"$T/$s.php.out" 2>&1; prc=$?
  timeout 10 "$T/aot_compile_rt2_${s}_tmp" >"$T/$s.aot.out" 2>&1; arc=$?
  php_n=$(norm < "$T/$s.php.out" | tr '\n' '|')
  aot_n=$(norm < "$T/$s.aot.out" | tr '\n' '|')
  if [ "$php_n" = "$aot_n" ]; then v=SAME; SAME_N=$((SAME_N + 1)); else v=DIFF; DIFF_N=$((DIFF_N + 1)); fi
  ph_class=$(grep -oE '(Cannot modify readonly property|Cannot assign [a-z]+ to property|Cannot access (private|protected) property|Undefined property:|Creation of dynamic property) [^ ]+' "$T/$s.php.out" | head -1 | awk '{print $NF}')
  ao_class=$(grep -oE '(Cannot modify readonly property|Cannot assign [a-z]+ to property|Cannot access (private|protected) property|Undefined property:|Creation of dynamic property) [^ ]+' "$T/$s.aot.out" | head -1 | awk '{print $NF}')
  if [ -z "$ph_class$ao_class" ]; then md=NA; elif [ "$ph_class" = "$ao_class" ]; then md=EQUAL; else md="php=$ph_class|aot=$ao_class"; fi
  echo "$s|php_rc=$prc|aot_rc=$arc|$v|msg_class_diff=$md|$php_n||aot=$aot_n" >> "$OUT"
done

echo "ELAPSED=$(($(date +%s) - START))s" >> "$OUT"
echo "RT002_DONE shapes=$COUNT same=$SAME_N diff=$DIFF_N compile_fail=$CF_N" >> "$OUT"
cat "$OUT"
