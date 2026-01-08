<?php

class Calculator {
    public function double($x) {
        return $x * 2;
    }

    public function apply($value) {
        $fn = fn($x) => $this->double($x);
        return $fn($value);
    }
}

$calc = new Calculator();
$result = $calc->apply(5);
echo "Result: $result\n";
