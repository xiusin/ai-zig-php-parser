<?php
// 闭包回调测试 5
$arr = [1, 2, 3, 4, 5];
$result = array_map(fn($x) => $x * 5, $arr);
echo implode(",", $result);
echo "
";
?>