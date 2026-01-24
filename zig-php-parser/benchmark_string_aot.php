<?php
// AOT模式字符串操作性能基准测试
echo "Starting string benchmark (AOT mode)...\n";

$iterations = 1000;
$result = "";

$i = 0;
while ($i < $iterations) {
    $result = $result . "x";
    $i = $i + 1;
}

echo "Completed ";
echo $iterations;
echo " string concatenations\n";
echo "Result length: ";
echo strlen($result);
echo "\n";
