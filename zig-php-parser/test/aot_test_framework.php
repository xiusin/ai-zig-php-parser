<?php
$passed = 0;
$failed = 0;
$errors = [];

function test($name, $condition) {
    global $passed, $failed, $errors;
    if ($condition) {
        $passed++;
        echo "[PASS] $name\n";
    } else {
        $failed++;
        $errors[] = $name;
        echo "[FAIL] $name\n";
    }
}

test("simple test", true);
test("failing test", false);

echo "Result: $passed passed, $failed failed\n";
