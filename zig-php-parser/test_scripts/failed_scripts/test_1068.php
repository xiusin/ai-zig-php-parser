<?php
// 混合类型比较测试 9
$values = [0, "0", "", false, null, []];
$a = $values[3];
$b = $values[5];
echo ($a == $b) ? "equal" : "notequal";
echo ($a === $b) ? "identical" : "notidentical";
echo "
";
?>