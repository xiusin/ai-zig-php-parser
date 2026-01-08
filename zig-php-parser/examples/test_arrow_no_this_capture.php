<?php

class Calculator {
    public function getArray() {
        return [1, 2, 3];
    }

    public function describeAll() {
        $arr = $this->getArray();
        return array_map(fn($x) => $x * 2, $arr);
    }

    public function describeAllNoThis() {
        $arr = $this->getArray();
        return array_map(fn($x) => $x * 3, $arr);
    }
}

$calc = new Calculator();
$result1 = $calc->describeAll();
echo "describeAll 1 done\n";

$result2 = $calc->describeAllNoThis();
echo "describeAllNoThis 1 done\n";

echo "Done\n";