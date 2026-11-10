<?php
// zend_sort 忠实移植验收：稳定性（等值元素保持原始相对序）+ 比较序列正确性
// 1) usort 稳定性（<=16 元素，插入排序路径）
$a = [];
for ($i = 0; $i < 12; $i++) $a[] = [$i % 3, $i];
usort($a, fn($x, $y) => $x[0] <=> $y[0]);
echo json_encode($a), "\n";

// 2) usort 稳定性（>16 元素，zend_sort 分区递归路径）
$b = [];
for ($i = 0; $i < 40; $i++) $b[] = [$i % 5, $i];
usort($b, fn($x, $y) => $x[0] <=> $y[0]);
echo json_encode($b), "\n";

// 3) uasort 稳定性 + 保键
$c = [];
for ($i = 0; $i < 20; $i++) $c["k$i"] = [$i % 3, $i];
uasort($c, fn($x, $y) => $x[0] <=> $y[0]);
echo json_encode($c), "\n";

// 4) uksort 键比较 + 保值关联
$d = ['b'=>1, 'a'=>2, 'd'=>3, 'c'=>4];
uksort($d, fn($x, $y) => strcmp($x, $y));
echo json_encode($d), "\n";

// 5) 正常排序回归：>16 元素完整正确性
$e = [9,3,7,1,8,2,6,4,0,5,15,13,11,17,12,10,19,14,16,18,25,21,23,22,20,24];
usort($e, fn($x, $y) => $x <=> $y);
echo json_encode($e), "\n";

// 6) 降序比较器
$f = [1,2,3,4,5];
usort($f, fn($x, $y) => $y <=> $x);
echo json_encode($f), "\n";

// 7) 大数组（>1024 元素，五点中值枢轴路径）
$g = [];
for ($i = 1100; $i > 0; $i--) $g[] = ($i * 37) % 101;
usort($g, fn($x, $y) => $x <=> $y);
$sorted = true;
for ($i = 1; $i < count($g); $i++) if ($g[$i-1] > $g[$i]) { $sorted = false; break; }
echo $sorted ? "sorted\n" : "NOT sorted\n";
echo json_encode(array_slice($g, 0, 5)), " ", json_encode(array_slice($g, -5)), "\n";
