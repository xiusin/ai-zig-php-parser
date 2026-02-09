<?php
$passed = 0;
$failed = 0;

function test() {
    global $passed, $failed;
    $passed++;
    echo "passed = $passed\n";
}

test();
echo "Final: passed=$passed, failed=$failed\n";
