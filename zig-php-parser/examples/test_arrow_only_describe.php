<?php

class Calculator {
    public function getArray() {
        return [1, 2, 3];
    }

    public function describeAll() {
        $arr = $this->getArray();
        return array_map(fn($x) => $x * 2, $arr);
    }

    public function getArray2() {
        return [4, 5, 6];
    }
}

$calc = new Calculator();
$calc->describeAll();
echo "describeAll done\n";

// Don't call getArray2

echo "Done\n";

