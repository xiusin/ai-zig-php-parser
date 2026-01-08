<?php

class Test {
    public function method() {
        $fn = fn() => $this->other();
        return $fn();
    }

    public function other() {
        return 42;
    }
}

$obj = new Test();
$result = $obj->method();
echo "Result: $result\n";

echo "Done\n";
