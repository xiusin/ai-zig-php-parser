<?php

class Calculator {
    public function describeAll() {
        $arr = [1, 2, 3];
        return array_map(function($x) { return $x * 2; }, $arr);
    }
}

$calc = new Calculator();
$result1 = $calc->describeAll();
echo "1 done\n";

$result2 = $calc->describeAll();
echo "2 done\n";

echo "Done\n";

