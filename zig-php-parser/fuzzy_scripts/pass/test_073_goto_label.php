<?php
// 测试73: goto语句与标签（虽然不推荐使用，但测试兼容性）
$i = 0;
start:
$i++;
if ($i <= 5) {
    echo "Iteration $i
";
    goto start;
}

// 跳出多层循环
for ($x = 0; $x < 3; $x++) {
    for ($y = 0; $y < 3; $y++) {
        if ($x == 1 && $y == 1) {
            goto end_loops;
        }
        echo "x=$x, y=$y
";
    }
}
end_loops:
echo "Loops ended
";

// 错误处理中使用
try {
    goto error_handler;
    echo "This won't print
";
} catch (Exception $e) {
    echo "Caught
";
}
error_handler:
echo "Error handler reached
";
?>