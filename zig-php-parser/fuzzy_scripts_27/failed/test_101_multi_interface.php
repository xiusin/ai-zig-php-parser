<?php
// Test 101: Multiple interfaces implementation
interface InterfaceA {
    public function methodA(): string;
}

interface InterfaceB {
    public function methodB(): string;
}

interface InterfaceC extends InterfaceA, InterfaceB {
    public function methodC(): string;
}

class MultiImpl implements InterfaceC {
    public function methodA(): string { return "A"; }
    public function methodB(): string { return "B"; }
    public function methodC(): string { return "C"; }
}

echo "=== Multiple interfaces ===\n";
$obj = new MultiImpl();
echo "methodA: " . $obj->methodA() . "\n";
echo "methodB: " . $obj->methodB() . "\n";
echo "methodC: " . $obj->methodC() . "\n";

echo "\n=== instanceof ===\n";
echo "obj instanceof InterfaceA: " . ($obj instanceof InterfaceA ? 'yes' : 'no') . "\n";
echo "obj instanceof InterfaceB: " . ($obj instanceof InterfaceB ? 'yes' : 'no') . "\n";
echo "obj instanceof InterfaceC: " . ($obj instanceof InterfaceC ? 'yes' : 'no') . "\n";

echo "\n=== Interface constants ===\n";
echo "InterfaceA::class: " . InterfaceA::class . "\n";
echo "InterfaceC::class: " . InterfaceC::class . "\n";