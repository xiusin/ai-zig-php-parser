<?php
// Test 122: Closure::call (PHP 8)
class A {
    public string $name = 'A';
}

class B {
    public string $name = 'B';
}

echo "=== Closure::call ===\n";
$getName = fn() => $this->name;

$a = new A();
$b = new B();

echo "Closure::call(\$a): " . $getName->call($a) . "\n";
echo "Closure::call(\$b): " . $getName->call($b) . "\n";

echo "\n=== Closure with args ===\n";
$add = fn(int $a, int $b) => $this->prefix . ($a + $b);

class Adder {
    public string $prefix = 'Sum: ';
}

class Subtracter {
    public string $prefix = 'Diff: ';
}

$adder = new Adder();
$subtracter = new Subtracter();

$addAdder = $add->bindTo($adder, Adder::class);
$addSubtracter = $add->bindTo($subtracter, Subtracter::class);

echo "Adder: " . $add->call($adder, 5, 3) . "\n";
echo "Subtracter: " . $add->call($subtracter, 5, 3) . "\n";