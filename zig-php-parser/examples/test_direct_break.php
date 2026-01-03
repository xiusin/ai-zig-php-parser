<?php

echo "测试直接 break:\n";
for range 5 as $i {
    echo "i = " . $i . "\n";
    if ($i == 2) {
        break;
    }
}
echo "循环结束\n";
