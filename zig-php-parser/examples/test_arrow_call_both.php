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

$calc->getArray2();
echo "getArray2 done\n";

echo "Done\n";
