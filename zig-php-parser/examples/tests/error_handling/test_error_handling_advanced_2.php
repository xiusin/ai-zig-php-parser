<?php
function testFinally($shouldThrow) {
    echo "Starting testFinally\n";
    try {
        echo "In try block\n";
        if ($shouldThrow) {
            throw new Exception("Thrown from try");
        }
        return "Return from try";
    } catch (Exception $e) {
        echo "In catch block: " . $e->getMessage() . "\n";
        return "Return from catch";
    } finally {
        echo "In finally block\n";
    }
    echo "This should never be printed\n";
}

echo "Test 1 (no throw):\n";
echo testFinally(false) . "\n";

echo "\nTest 2 (with throw):\n";
echo testFinally(true) . "\n";
?>