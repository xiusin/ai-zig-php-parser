<?php
// 测试简单while循环优化
$i = 0;
while ($i < 5) {
    echo "i = ";
    echo $i;
    echo "\n";
    $i = $i + 1;
}
echo "Done!\n";
