<?php
// Test 033: Autoloading simulation, class loading, and include/require
class AutoloadLab {
    private array $loadedClasses = [];

    public function simulateAutoload(string $className): bool {
        $this->loadedClasses[$className] = true;
        return true;
    }

    public function isLoaded(string $className): bool {
        return isset($this->loadedClasses[$className]);
    }

    public function getLoadedCount(): int {
        return count($this->loadedClasses);
    }
}

function my_autoloader(string $class): void {
    echo "Autoloading: $class\n";
}

echo "=== Autoload simulation ===\n";
$lab = new AutoloadLab();

$lab->simulateAutoload('ClassA');
$lab->simulateAutoload('ClassB');
$lab->simulateAutoload('ClassA');

echo "ClassA loaded: " . ($lab->isLoaded('ClassA') ? 'yes' : 'no') . "\n";
echo "ClassC loaded: " . ($lab->isLoaded('ClassC') ? 'yes' : 'no') . "\n";
echo "Total loaded: " . $lab->getLoadedCount() . "\n";

echo "\n=== Class exists and method exists ===\n";
echo "class_exists('stdClass'): " . (class_exists('stdClass') ? 'yes' : 'no') . "\n";
echo "class_exists('NonExistentClass'): " . (class_exists('NonExistentClass') ? 'yes' : 'no') . "\n";
echo "interface_exists('Countable'): " . (interface_exists('Countable') ? 'yes' : 'no') . "\n";
echo "trait_exists('ArrayObject'): " . (trait_exists('ArrayObject') ? 'yes' : 'no') . "\n";

class TestMethod {
    public function publicMethod(): string { return "public"; }
    private function privateMethod(): string { return "private"; }
    static public function staticMethod(): string { return "static"; }
}

$obj = new TestMethod();
echo "method_exists(\$obj, 'publicMethod'): " . (method_exists($obj, 'publicMethod') ? 'yes' : 'no') . "\n";
echo "method_exists(\$obj, 'privateMethod'): " . (method_exists($obj, 'privateMethod') ? 'yes' : 'no') . "\n";
echo "is_callable([\$obj, 'publicMethod']): " . (is_callable([$obj, 'publicMethod']) ? 'yes' : 'no') . "\n";

echo "\n=== Property exists ===\n";
class PropTest {
    public string $public = 'public';
    private string $private = 'private';
    static string $static = 'static';
}

$p = new PropTest();
echo "property_exists(\$p, 'public'): " . (property_exists($p, 'public') ? 'yes' : 'no') . "\n";
echo "property_exists(\$p, 'private'): " . (property_exists($p, 'private') ? 'yes' : 'no') . "\n";
echo "property_exists('PropTest', 'static'): " . (property_exists('PropTest', 'static') ? 'yes' : 'no') . "\n";

echo "\n=== is_subclass_of and instanceof ===\n";
class ParentClass {}
class ChildClass extends ParentClass {}

$child = new ChildClass();
echo "is_subclass_of('ChildClass', 'ParentClass'): " . (is_subclass_of('ChildClass', 'ParentClass') ? 'yes' : 'no') . "\n";
echo "\$child instanceof ParentClass: " . ($child instanceof ParentClass ? 'yes' : 'no') . "\n";