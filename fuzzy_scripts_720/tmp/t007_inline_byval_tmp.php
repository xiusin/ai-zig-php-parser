<?php
/**
 * 永久探针（AOT-CODEGEN-007 复现 B：内联 + 按值形参 ⇒ 生成码可编译但形参取错值）
 *
 * 同一机制（optimizer.zig:4861 `.param => op` 不做实参替换），但目标寄存器为 Value
 *   ⇒ 类型检查通过 ⇒ 静默取 caller 帧的 args[]（在 __main__ 即 argv ⇒ 缺参为 null）。
 * 本探针把「编译期报错」与「运行期静默错值」两种后果分开取证。
 *
 * 真值：PHP 输出 B1=5 B2=30
 */

function t007_plus(int $a, int $b): int
{
    return $a + $b;
}

$u = 10;
$v = 20;
echo "B1=" . t007_plus(2, 3) . "\n";
echo "B2=" . t007_plus($u, $v) . "\n";
