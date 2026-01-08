<?php

class Test {
    public function method() {
        $result = $this->other();
        echo "Result: $result\n";
    }

    public function other() {
        return 42;
    }
}

$obj = new Test();
$obj->method();
echo "Done\n";

