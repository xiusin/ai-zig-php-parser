<?php

class Test {
    public function method() {
        $fn = fn() => 42;
        $result = $fn();
        echo "Result: $result\n";
    }

    public function other() {
        return 42;
    }
}

$obj = new Test();
$obj->method();
$obj->other();
echo "Done\n";
