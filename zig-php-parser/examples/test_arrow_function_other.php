<?php

function other() {
    return 42;
}

class Test {
    public function getArray() {
        return [1, 2, 3];
    }

    public function method() {
        $arr = $this->getArray();
        $result = array_map(fn($x) => $x * 2, $arr);
        echo "Mapped\n";
    }
}

$obj = new Test();
$obj->method();

$result2 = other();
echo "Other: $result2\n";

echo "Done\n";
