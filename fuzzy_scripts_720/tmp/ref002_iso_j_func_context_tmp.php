<?php
// 隔离探针 J：F 的形状放进**函数**体内（foreach 的 cleanup 不再以 main 的 return 终结）。
// 目的：查清 CODEGEN-005 第二个丢失点（loop_end 截断）在函数上下文里的表现——
// 若内层 for 被外层行走补发在循环之外，则缺陷形态从「丢失」变成「位置错误」，
// 修复验收面需同时覆盖两种上下文。
function runJ($seed) {
    $a = [];
    for ($i = 0; $i < 20; $i++) {
        $a['k' . $i] = $i;
    }
    $hits = 0;
    foreach ($a as $key => $value) {
        $hits++;
        if ($hits === $seed) {
            for ($j = 0; $j < 40; $j++) {
                $a['g' . $j] = -$j;
            }
        }
        if ($hits > 3) {
            break;
        }
    }
    return "J hits=" . $hits . " count=" . count($a) . "\n";
}
echo runJ(1);
