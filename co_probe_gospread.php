<?php
// 临时探针：go 语句形 + 展开 的最小复现
function gs($a, $b, $c) {
    echo "gs=" . ($a + $b + $c) . "\n";
}
$args = [7, 8];
go gs(1, ...$args);
go_wait_all();
echo "DONE\n";
