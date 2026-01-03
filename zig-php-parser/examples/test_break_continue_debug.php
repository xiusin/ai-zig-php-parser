<?php

echo "测试 continue:\n";
for range 5 as $i {
    if ($i == 2) {
        echo "跳过 i=2\n";
        continue;
    }
    echo "i = " . $i . "\n";
}

echo "\n测试 break:\n";
$n = 0;
while ($n < 10) {
    $n = $n + 1;
    echo "n = " . $n . "\n";
    if ($n == 3) {
        echo "退出循环\n";
        break;
    }
}
echo "循环结束，n = " . $n . "\n";
