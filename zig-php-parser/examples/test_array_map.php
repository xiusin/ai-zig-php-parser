<?php

echo "测试array_map\n";

$numbers = [1, 2, 3];

$squared = array_map(function($x) { return $x * $x; }, $numbers);

echo "原数组: ";
foreach ($numbers as $n) {
    echo $n . " ";
}
echo "\n";

echo "平方后: ";
foreach ($squared as $n) {
    echo $n . " ";
}
echo "\n";

?>
