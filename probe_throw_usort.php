<?php
// usort 比较器抛异常：数组抛后状态
$a = [3, 1, 2, 5, 4];
$calls = 0;
try {
    usort($a, function($x, $y) use (&$calls) {
        $calls++;
        if ($calls >= 3) throw new Exception("boom");
        return $x <=> $y;
    });
} catch (Exception $e) {
    echo "caught: ", $e->getMessage(), "\n";
}
echo "calls=$calls\n";
echo json_encode($a), "\n";
sort($a); // 规范化看元素集合是否保持
echo json_encode($a), "\n";
