<?php

class Test {
    public function getArray() {
        return [1, 2, 3];
    }

    public function method() {
        $arr = $this->getArray();
        $result = array_map(fn($x) => $x * 2, $arr);
        // Don't return the result
        echo "Mapped\n";
    }

    public function other() {
        return 42;
    }
}

$obj = new Test();
$obj->method();

$result2 = $obj->other();
echo "Other: $result2\n";

echo "Done\n";
