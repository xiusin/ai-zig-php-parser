<?php
// 简单throw语句测试

function testThrow() {
    throw new Exception("Test exception");
}

try {
    testThrow();
} catch (Exception $e) {
    echo "Caught exception: " . $e->getMessage() . "\n";
}

echo "Test completed successfully\n";
?>
