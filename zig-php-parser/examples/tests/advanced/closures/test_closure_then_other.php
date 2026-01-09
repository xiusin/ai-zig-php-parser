<?php

class Test {
    public function getArray() {
        return [1, 2, 3];
    }

    public function method() {
        $arr = $this->getArray();
        $result = array_map(function($x) { return $x * 2; }, $arr);
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
