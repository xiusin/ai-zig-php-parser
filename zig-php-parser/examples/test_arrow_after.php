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
$result = $calc->describeAll();
echo "Result: ";
print_r($result);

// Call another method after array_map
$arr2 = $calc->getArray2();
echo "Array2: ";
print_r($arr2);
