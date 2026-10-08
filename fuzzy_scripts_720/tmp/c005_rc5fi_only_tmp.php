<?php
// 永久取证探针：AOT-CODEGEN-005 do-while 侧同族第三站点单形隔离（F-I）。
// 几何与 F-F 逐字同构，只把臂内嵌循环从 while 换成 do-while（外层 foreach + 臂内嵌 do-while + 臂尾裸 continue + 兄弟语句 $hit++）。
// 立探针目的：`generateDoWhileFromLabels`（:17317–:17426）在 :17395–:17400 对外层 latch
//   （for_loop_/foreach_increment_）走「processed.put + return exit_idx + 1」且**不记录** last_loop_fallthrough_idx，
//   与 facet-2 落地前的 for 站点② 同形 ⇒ 审计该形态是否仍在过执行。
// 真值：visited=4 hit=2 count_x=4（foreach 4 轮，前 2 轮走臂并 continue 跳过 $hit++，后 2 轮执行 $hit++）。

function rc5fi_mk(int $n): array {
    $a = [];
    for ($i = 0; $i < $n; $i++) {
        $a['k' . $i] = $i;
    }
    return $a;
}

$b = rc5fi_mk(4);
$w = 0;
$hit = 0;
$x = [];
foreach ($b as $key => $val) {
    $w++;
    if ($w < 3) {
        $k = 0;
        do {
            $x[$w . "_" . $k] = $k;
            $k++;
        } while ($k < 2);
        continue;
    }
    $hit++;
}
echo "F-I visited={$w} hit={$hit} count_x=" . count($x) . "\n";
