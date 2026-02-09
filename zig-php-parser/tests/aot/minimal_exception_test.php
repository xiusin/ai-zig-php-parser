<?php

class MyException extends Exception {}

function test(int $x): void {
    if ($x < 0) {
        throw new MyException("Negative");
    }
    echo "OK: $x\n";
}

// 第一次调用 - 正常
try {
    test(5);
} catch (MyException $e) {
    echo "Caught: " . $e->getMessage() . "\n";
}

// 第二次调用 - 抛出异常
try {
    test(-1);
} catch (MyException $e) {
    echo "Caught: " . $e->getMessage() . "\n";
}

// 第三次调用 - 正常
try {
    test(10);
} catch (MyException $e) {
    echo "Caught: " . $e->getMessage() . "\n";
}
