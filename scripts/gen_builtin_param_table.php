<?php
/**
 * 批次十九①：内建函数形参名表生成器（批次十八①评估落地）。
 *
 * 数据来源：PHP 8.5.8 自身反射（ReflectionFunction/ReflectionParameter），
 * 全量 2143 枚内建函数，零手抄。如实标注：默认值不可反射 ⇒ .unknown；
 * 数组默认值（标量族外）⇒ .unknown（不拿空串/0 冒充）。
 *
 * 重跑命令（仓库根目录）：
 *   php scripts/gen_builtin_param_table.php
 * 产物：src/aot/builtin_param_table_generated.zig（进版本库；diff 复核即可审计）。
 */
error_reporting(E_ALL & ~E_DEPRECATED & ~E_USER_DEPRECATED);
ini_set('serialize_precision', '-1'); // 浮点最短往返表示

$root = dirname(__DIR__);
$out_path = $root . '/src/aot/builtin_param_table_generated.zig';

/** 默认值 → Zig 字面量片段（诚实口径：不可表示一律 unknown） */
function defaultToZig(ReflectionParameter $p): array
{
    if ($p->isVariadic()) {
        return ['none', '']; // 变参无默认语义
    }
    if (!$p->isOptional()) {
        return ['none', '']; // 必填 ⇒ 无默认（不是 unknown）
    }
    if (!$p->isDefaultValueAvailable()) {
        // 可选但默认值不可反射（PHP 内部常量表达式等）——如实标注
        return ['unknown', ''];
    }
    $v = $p->getDefaultValue();
    switch (true) {
        case is_null($v):
            return ['null_', ''];
        case is_bool($v):
            return ['boolean', ', .b = ' . ($v ? 'true' : 'false')];
        case is_int($v):
            return ['int', ', .i = ' . (string) $v];
        case is_float($v):
            // var_export 在 serialize_precision=-1 下给最短往返字面量（0.1 / 1.0 / 2.5E-3）
            return ['float', ', .f = ' . var_export($v, true)];
        case is_string($v):
            // 逐字节转义：Zig 字符串字面量禁裸控制字节（\v/\f/\0 等一律 \xNN；UTF-8 高位直通）
            $esc = '';
            foreach (str_split($v) as $ch) {
                $o = ord($ch);
                if ($ch === '\\') $esc .= '\\\\';
                elseif ($ch === '"') $esc .= '\\"';
                elseif ($ch === "\n") $esc .= '\\n';
                elseif ($ch === "\r") $esc .= '\\r';
                elseif ($ch === "\t") $esc .= '\\t';
                elseif ($o < 0x20 || $o === 0x7f) $esc .= sprintf('\\x%02x', $o);
                else $esc .= $ch;
            }
            return ['str', ', .s = "' . $esc . '"'];
        default:
            // 数组/常量表达式等其它形态：不冒充，标 unknown
            return ['unknown', ''];
    }
}

$names = get_defined_functions()['internal'];
sort($names); // 稳定输出 ⇒ diff 可复核

/** 形参类型 → [type_name 原文（联合 | 连接）, nullable]。
 *  无类型 ⇒ ["", true]（mixed 语义同：任意值含 null，Deprecated-null 不警）。 */
function typeToZig(ReflectionParameter $p): array
{
    $t = $p->getType();
    if ($t === null) return ['', true];
    $nullable = $t->allowsNull();
    if ($t instanceof ReflectionNamedType) {
        return [$t->getName(), $nullable];
    }
    if ($t instanceof ReflectionUnionType) {
        $parts = [];
        foreach ($t->getTypes() as $u) {
            $parts[] = $u instanceof ReflectionNamedType ? $u->getName() : (string) $u;
        }
        return [implode('|', $parts), $nullable];
    }
    // 交叉类型（A&B）：Deprecated-null 域不触及（非标量）⇒ 如实记原文
    return [(string) $t, $nullable];
}

$stats = ['fn' => 0, 'param' => 0, 'unknown_default' => 0, 'variadic' => 0, 'by_ref' => 0];
$lines = [];
foreach ($names as $fn) {
    try {
        $rf = new ReflectionFunction($fn);
    } catch (Throwable $e) {
        continue;
    }
    $ps = [];
    foreach ($rf->getParameters() as $p) {
        [$dk, $dv] = defaultToZig($p);
        $stats['param']++;
        if ($dk === 'unknown') $stats['unknown_default']++;
        if ($p->isVariadic()) $stats['variadic']++;
        if ($p->isPassedByReference()) $stats['by_ref']++;
        $pname = strtr($p->name, ["\\" => "\\\\", '"' => '\\"']);
        [$tname, $tnullable] = typeToZig($p);
        $tname_esc = strtr($tname, ["\\" => "\\\\", '"' => '\\"']);
        $ps[] = sprintf(
            '.{ .name = "%s", .optional = %s, .variadic = %s, .by_ref = %s, .type_name = "%s", .nullable = %s, .default = %s }',
            $pname,
            $p->isOptional() ? 'true' : 'false',
            $p->isVariadic() ? 'true' : 'false',
            $p->isPassedByReference() ? 'true' : 'false',
            $tname_esc,
            $tnullable ? 'true' : 'false',
            $dv === '' ? '.{ .kind = .' . $dk . ' }' : '.{ .kind = .' . $dk . $dv . ' }'
        );
    }
    $stats['fn']++;
    // 键：小写函数名（运行侧 CI 折叠同口径；PHP 内建名本身全小写，alias 如 join 独立成行）
    $lines[] = '.{ "' . strtr(strtolower($fn), ["\\" => "\\\\", '"' => '\\"']) . '", &[_]Param{' . implode(', ', $ps) . '} },';
}

$header = <<<'ZIG'
//! AUTO-GENERATED — 批次十九① 内建函数形参名表。请勿手改。
//!
//! 数据来源：PHP 8.5.8 反射（get_defined_functions + ReflectionParameter）。
//! 重跑命令（仓库根目录）：php scripts/gen_builtin_param_table.php
//! 生成统计：%STATS%
//!
//! 诚实口径：default.kind == .unknown ⇒ 「可选但默认值反射不出」（不拿空串/0 冒充）；
//! 调用点遇 .unknown 的行为按工单 §247.3/§248 的登记边界处理，不发明兜底。

const std = @import("std");

/// 形参默认值（扁平载荷；unknown 为如实标注位——不拿空串/0 冒充）
pub const DefaultVal = struct {
    pub const Kind = enum { none, unknown, null_, boolean, int, float, str };
    kind: Kind = .none,
    b: bool = false,
    i: i64 = 0,
    f: f64 = 0,
    s: []const u8 = "",
};

pub const Param = struct {
    name: []const u8,
    optional: bool,
    variadic: bool,
    by_ref: bool,
    /// ★Deprecated-null（批次二十四续）：类型原文（联合 `|` 连接，如 "int|float"）；
    ///   "" ＝ 无类型声明（mixed 语义同：任意值含 null，不警）。
    type_name: []const u8 = "",
    /// allowsNull 反射位（?T / mixed / 无类型 ⇒ true）。
    nullable: bool = true,
    default: DefaultVal,
};

/// arity 三元组（required / 非变参声明总数 / 是否含变参）
pub const ArityInfo = struct { min: usize, max: usize, has_variadic: bool };

/// 按名查 arity（表键小写；函数名 CI ⇒ 内部折叠，≤64 栈缓冲）。编译期（native_linker）
/// 与运行期（runtime_lib_template）共用同一份判定，禁两处各造。
pub fn arityOf(name: []const u8) ?ArityInfo {
    const params = table.get(name) orelse blk: {
        if (name.len > 64) return null;
        var lbuf: [64]u8 = undefined;
        break :blk table.get(std.ascii.lowerString(&lbuf, name));
    } orelse return null;
    var min: usize = 0;
    var max: usize = 0;
    var has_variadic = false;
    for (params) |p| {
        if (p.variadic) {
            has_variadic = true;
            continue;
        }
        max += 1;
        if (!p.optional) min += 1;
    }
    return .{ .min = min, .max = max, .has_variadic = has_variadic };
}

/// 小写函数名 ⇒ 形参表（声明序）
pub const table = std.StaticStringMap([]const Param).initComptime(.{
ZIG;

$statsLine = sprintf('fn=%d param=%d unknown_default=%d variadic=%d by_ref=%d', $stats['fn'], $stats['param'], $stats['unknown_default'], $stats['variadic'], $stats['by_ref']);
$header = str_replace('%STATS%', $statsLine, $header);

$body = $header . "\n" . implode("\n", array_map(fn($l) => '    ' . $l, $lines)) . "\n});\n";
file_put_contents($out_path, $body);
fwrite(STDERR, "written: $out_path ($statsLine)\n");
