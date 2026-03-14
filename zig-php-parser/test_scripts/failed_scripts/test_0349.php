<?php
// break/continue测试 3
$sum = 0;
for ($i = 0; $i < 20; $i++) {
    if ($i % 2 == 0) continue;
    if ($i > 10) break;
    $sum += $i;
}
echo $sum;
echo "
";
?>