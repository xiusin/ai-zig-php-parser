<?php

class Test {
    public function method() {
        $result = array_map(fn($x) => $this->other() + $x, [1, 2, 3]);
        echo "Result: " . implode(",", $result) . "\n";
    }

    public function other() {
        return 10;
    }
}

$obj = new Test();
$obj->method();
echo "Done\n";