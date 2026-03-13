<?php
// 闭包测试 1
$factor = 2;
$multiply = function($x) use ($factor) {
    return $x * $factor;
};
echo $multiply(6);
echo "
";
?>