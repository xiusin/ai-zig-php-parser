<?php
// Test 153: Closure binding and scope
class BindingA {
    public string $name = 'A';
}

class BindingB {
    public string $name = 'B';
}

echo "=== Closure binding ===\n";
$getName = function() {
    return $this->name;
};

$a = new BindingA();
$b = new BindingB();

$fromA = Closure::bind($getName, $a, BindingA::class);
$fromB = Closure::bind($getName, $b, BindingB::class);

echo "From A: " . $fromA() . "\n";
echo "From B: " . $fromB() . "\n";