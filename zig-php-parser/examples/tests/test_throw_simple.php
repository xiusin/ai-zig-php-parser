<?php
// 简单的throw测试

function test1() {
    throw new Exception("Test exception");
}

try {
    test1();
} catch (Exception $e) {
    echo "Caught: " . $e->getMessage() . "\n";
}

echo "Test passed\n";
?>
