<?php
// use引用测试 5
$total = 0;
$adder = function($x) use (&$total) {
    $total += $x;
};
$adder(1);
$adder(2);
$adder(3);
echo $total;
echo "
";
?>