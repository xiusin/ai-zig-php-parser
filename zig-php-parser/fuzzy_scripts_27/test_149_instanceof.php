<?php
// Test 149: instanceof with expressions
class Base {}
class Child extends Base {}
class Unrelated {}

$base = new Base();
$child = new Child();

echo "=== instanceof ===\n";
echo "\$child instanceof Base: " . ($child instanceof Base ? 'yes' : 'no') . "\n";
echo "\$base instanceof Child: " . ($base instanceof Child ? 'yes' : 'no') . "\n";
echo "\$child instanceof Base: " . ($child instanceof Base ? 'yes' : 'no') . "\n";

echo "\n=== Interface instanceof ===\n";
interface TestI {}
class Impl implements TestI {}
$impl = new Impl();
echo "\$impl instanceof TestI: " . ($impl instanceof TestI ? 'yes' : 'no') . "\n";