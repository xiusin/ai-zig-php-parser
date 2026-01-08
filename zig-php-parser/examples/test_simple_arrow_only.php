<?php

class Test {
    public function method() {
        $fn = fn() => 42;
        $result = $fn();
        echo "Result: $result\n";
    }
}

$obj = new Test();
$obj->method();
echo "Done\n";

