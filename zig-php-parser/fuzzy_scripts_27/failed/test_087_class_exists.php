<?php
// Test 087: Class_exists, interface_exists, trait_exists
interface TestInterface {}
trait TestTrait {}
class TestClass {}

echo "=== Exists checks ===\n";
echo "class_exists('TestClass'): " . (class_exists('TestClass') ? 'yes' : 'no') . "\n";
echo "class_exists('NonExistent'): " . (class_exists('NonExistent') ? 'yes' : 'no') . "\n";
echo "interface_exists('TestInterface'): " . (interface_exists('TestInterface') ? 'yes' : 'no') . "\n";
echo "trait_exists('TestTrait'): " . (trait_exists('TestTrait') ? 'yes' : 'no') . "\n";

echo "\n=== Method exists ===\n";
class MethodTest {
    public function publicMethod() {}
    private function privateMethod() {}
}

$obj = new MethodTest();
echo "method_exists(\$obj, 'publicMethod'): " . (method_exists($obj, 'publicMethod') ? 'yes' : 'no') . "\n";
echo "method_exists(\$obj, 'privateMethod'): " . (method_exists($obj, 'privateMethod') ? 'yes' : 'no') . "\n";
echo "is_callable([\$obj, 'publicMethod']): " . (is_callable([$obj, 'publicMethod']) ? 'yes' : 'no') . "\n";

echo "\n=== Property exists ===\n";
class PropTest {
    public $public = 'public';
    private $private = 'private';
}

$p = new PropTest();
echo "property_exists(\$p, 'public'): " . (property_exists($p, 'public') ? 'yes' : 'no') . "\n";
echo "property_exists(\$p, 'private'): " . (property_exists($p, 'private') ? 'yes' : 'no') . "\n";
echo "property_exists('PropTest', 'public'): " . (property_exists('PropTest', 'public') ? 'yes' : 'no') . "\n";

echo "\n=== is_subclass_of ===\n";
class ParentClass {}
class ChildClass extends ParentClass {}

echo "is_subclass_of('ChildClass', 'ParentClass'): " . (is_subclass_of('ChildClass', 'ParentClass') ? 'yes' : 'no') . "\n";
echo "is_subclass_of('ParentClass', 'ParentClass'): " . (is_subclass_of('ParentClass', 'ParentClass') ? 'yes' : 'no') . "\n";