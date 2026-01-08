<?php

class Calculator {
    public function getArray() {
        return [1, 2, 3];
    }

    public function describeAll() {
        $arr = $this->getArray();
        return array_map(fn($x) => $x * 2, $arr);
    }
}

$calc = new Calculator();
$calc->describeAll();
echo "describeAll 1 done\n";

$calc->describeAll();
echo "describeAll 2 done\n";

echo "Done\n";

