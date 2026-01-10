<?php
// while 循环测试
$i = 0;
while ($i < 5) {
    echo "i = $i\n";
    $i++;
}

// for 循环测试
for ($j = 0; $j < 3; $j++) {
    echo "j = $j\n";
}

// foreach 测试
$array = [1, 2, 3];
foreach ($array as $value) {
    echo "value = $value\n";
}
?>