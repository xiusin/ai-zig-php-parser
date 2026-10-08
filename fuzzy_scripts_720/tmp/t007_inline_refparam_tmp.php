<?php
/**
 * 永久探针（AOT-CODEGEN-007 复现 A：内联 + 按引用形参 ⇒ 生成码类型错误 ⇒ 整脚本编译失败）
 *
 * 触发档：--optimize=release-fast / release-safe（function_inlining=true）
 * 默认档（release_small，function_inlining=false）不触发 ⇒ 与冻结基线 68 语料正交
 *
 * 机制：optimizer.zig:4861 的 remapInstructionOp 对 `.param => op` 原样返回（不做实参替换），
 *   内联体因此保留 callee 的「从 args[] 取形参」指令，在 caller 帧里读的是 caller 自己的 args。
 *   callee 的引用形参寄存器为 *Value（ref_ptr），而 native_linker.zig:21170–:21193 的
 *   「普通参数 COW」支只按 is_alloca 判别目标类型 ⇒ 向 *Value 寄存器写入 Value ⇒ Zig 类型错误。
 */

function t007_ap(array &$a): void
{
    $a[] = 9;
}

$x = [1, 2];
t007_ap($x);
echo "A count=" . count($x) . " last=" . $x[2] . "\n";
