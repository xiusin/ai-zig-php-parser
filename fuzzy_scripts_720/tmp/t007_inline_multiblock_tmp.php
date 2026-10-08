<?php
/**
 * 永久探针（AOT-CODEGEN-007 复现 C：内联只搬 callee 入口块 ⇒ 多块函数体被整段丢弃）
 *
 * 门不一致：can_inline 允许 block_count ≤ 6（optimizer.zig:4592），
 *   而 inlineFunction 只要求 blocks ≤ 3（:4682）却仅克隆入口块指令（:4711）与入口块终止符的 .ret（:4720）。
 *   ⇒ 2~3 块的 callee 被内联时，第 2 块起的所有语句与返回值映射全部丢失。
 *
 * 真值：PHP 输出 D=1 0
 */

function t007_cmp(int $a): int
{
    if ($a > 5) {
        return 1;
    }
    return 0;
}

echo "D=" . t007_cmp(9) . " " . t007_cmp(1) . "\n";
