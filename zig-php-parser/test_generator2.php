<?php
class SimpleGen {
    public function gen() {
        yield 1;
        yield 2;
        yield 3;
    }
}

$gen = new SimpleGen();
$result = $gen->gen();
echo "Class: " . get_class($result) . "\n";
echo "Is Generator: " . ($result instanceof Generator ? "yes" : "no") . "\n";

// Try to iterate
foreach ($result as $value) {
    echo "Value: $value\n";
}

