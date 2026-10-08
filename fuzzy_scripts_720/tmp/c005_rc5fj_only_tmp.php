<?php
// 永久取证探针：AOT-CODEGEN-005 do-while 侧同族第三站点单形隔离（F-J，外层 for 版）。
// 几何与 F-H 逐字同构，只把臂内嵌循环从 for 换成 do-while（外层 for + 臂内嵌 do-while + 臂尾裸 continue + 兄弟语句 $hit++）。
// 与 F-I（外层 foreach）成对，用于判定 do-while 站点③ 的外层 latch 前缀是否两类（foreach_increment_ / for_loop_）同判据。
// 真值：hit=1 count_x=6（外层 4 轮，前 3 轮走臂并 continue 跳过 $hit++，仅第 4 轮执行 $hit++）。

$hit = 0;
$x = [];
for ($i = 0; $i < 4; $i++) {
    $w = $i;
    if ($w < 3) {
        $j = 0;
        do {
            $x[$i . "_" . $j] = $j;
            $j++;
        } while ($j < 2);
        continue;
    }
    $hit++;
}
echo "F-J hit={$hit} count_x=" . count($x) . "\n";
