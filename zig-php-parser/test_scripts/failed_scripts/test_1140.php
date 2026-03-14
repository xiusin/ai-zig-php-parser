<?php
// 多层嵌套测试 11
$result = [];
for ($a = 0; $a < 3; $a++) {
    for ($b = 0; $b < 3; $b++) {
        if ($a + $b > 2) {
            $result[] = $a * 10 + $b;
        }
    }
}
echo implode(",", $result);
echo "
";
?>