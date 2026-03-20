<?php
// Test 056: Interface inheritance, multiple interfaces
interface A {
    public const A_CONST = 'A';
    public function methodA(): string;
}

interface B {
    public const B_CONST = 'B';
    public function methodB(): string;
}

interface C extends A, B {
    public const C_CONST = 'C';
    public function methodC(): string;
}

interface D {
    public function methodD(): string;
}

class ImplABC implements C {
    public function methodA(): string { return "A"; }
    public function methodB(): string { return "B"; }
    public function methodC(): string { return "C"; }
}

class ImplAB implements A, B {
    public function methodA(): string { return "A"; }
    public function methodB(): string { return "B"; }
}

class ImplAll implements A, B, D {
    public function methodA(): string { return "A"; }
    public function methodB(): string { return "B"; }
    public function methodD(): string { return "D"; }
}

echo "=== Interface constants ===\n";
echo "A::A_CONST: " . A::A_CONST . "\n";
echo "B::B_CONST: " . B::B_CONST . "\n";
echo "C::C_CONST: " . C::C_CONST . "\n";
echo "C extends A, B - A_CONST: " . C::A_CONST . "\n";
echo "C extends A, B - B_CONST: " . C::B_CONST . "\n";

echo "\n=== Implementation checks ===\n";
$abc = new ImplABC();
$ab = new ImplAB();
$all = new ImplAll();

echo "ImplABC instanceof A: " . ($abc instanceof A ? 'yes' : 'no') . "\n";
echo "ImplABC instanceof B: " . ($abc instanceof B ? 'yes' : 'no') . "\n";
echo "ImplABC instanceof C: " . ($abc instanceof C ? 'yes' : 'no') . "\n";

echo "ImplAB instanceof A: " . ($ab instanceof A ? 'yes' : 'no') . "\n";
echo "ImplAB instanceof B: " . ($ab instanceof B ? 'yes' : 'no') . "\n";

echo "ImplAll instanceof A: " . ($all instanceof A ? 'yes' : 'no') . "\n";
echo "ImplAll instanceof D: " . ($all instanceof D ? 'yes' : 'no') . "\n";

echo "\n=== Interface method calls ===\n";
echo "abc->methodA(): " . $abc->methodA() . "\n";
echo "abc->methodB(): " . $abc->methodB() . "\n";
echo "abc->methodC(): " . $abc->methodC() . "\n";

echo "\n=== Reflection on interfaces ===\n";
$rc = new ReflectionClass(C::class);
echo "C is interface: " . ($rc->isInterface() ? 'yes' : 'no') . "\n";
echo "C implemented interfaces: " . implode(', ', $rc->getInterfaceNames()) . "\n";