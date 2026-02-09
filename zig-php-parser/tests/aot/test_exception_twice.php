<?php

class MyException extends Exception {}

function test1(): void {
    echo "In test1\n";
    throw new MyException("Test 1");
}

echo "Start\n";

// 第一次调用
try {
    echo "Before test1 call 1\n";
    test1();
    echo "After test1 call 1\n";
} catch (MyException $e) {
    echo "Caught 1: " . $e->getMessage() . "\n";
}

echo "Between calls\n";

// 第二次调用
try {
    echo "Before test1 call 2\n";
    test1();
    echo "After test1 call 2\n";
} catch (MyException $e) {
    echo "Caught 2: " . $e->getMessage() . "\n";
}

echo "End\n";
