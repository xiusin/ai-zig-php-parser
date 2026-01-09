<?php
function simulateTask($name, $duration) {
    echo $name . " started (duration: " . $duration . "s)\n";
    $start = time();
    while ((time() - $start) < $duration) {
        // 模拟工作
    }
    echo $name . " completed\n";
    return $name . " result";
}

echo "=== Sequential execution ===\n";
$result1 = simulateTask("Task1", 1);
$result2 = simulateTask("Task2", 1);
echo "Results: " . $result1 . ", " . $result2 . "\n";
?>