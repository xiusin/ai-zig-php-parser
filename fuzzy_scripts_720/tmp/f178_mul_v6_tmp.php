<?php
// f178 排查探针 v6：三层 for + 内层假边落带指令的 for_exit_ 尾（j 尾块融合 set/add）
function mul3(int $n): int {
    $x = 0;
    for ($i = 0; $i < $n; $i++) {
        for ($j = 0; $j < $n; $j++) {
            $sum = 0;
            for ($k = 0; $k < $n; $k++) {
                $sum = $sum + 1;
            }
            $x = $x + $sum;
        }
    }
    return $x;
}
echo "=== f178 v6 ===\n";
echo "mul3(3)=" . mul3(3) . "\n";
echo "=== done ===\n";
