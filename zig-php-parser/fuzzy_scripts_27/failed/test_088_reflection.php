<?php
// Test 088: ReflectionClass
class ReflectionTarget {
    public string $publicProp = 'public';
    private string $privateProp = 'private';

    public function publicMethod(): string {
        return 'public_method';
    }

    private function privateMethod(): string {
        return 'private_method';
    }
}

echo "=== ReflectionClass ===\n";
$rc = new ReflectionClass(ReflectionTarget::class);
echo "Name: " . $rc->getName() . "\n";
echo "Is class: " . ($rc->isClass() ? 'yes' : 'no') . "\n";
echo "Is instantiable: " . ($rc->isInstantiable() ? 'yes' : 'no') . "\n";
echo "Is interface: " . ($rc->isInterface() ? 'yes' : 'no') . "\n";

echo "\n=== Properties ===\n";
foreach ($rc->getProperties() as $prop) {
    $visibility = $prop->isPublic() ? 'public' : ($prop->isProtected() ? 'protected' : 'private');
    echo "  {$prop->getName()}: $visibility\n";
}

echo "\n=== Methods ===\n";
foreach ($rc->getMethods() as $method) {
    $visibility = $method->isPublic() ? 'public' : ($method->isProtected() ? 'protected' : 'private');
    echo "  {$method->getName()}(): $visibility\n";
}

echo "\n=== Constants ===\n";
$rc2 = new ReflectionClass(stdClass::class);
foreach ($rc2->getConstants() as $name => $value) {
    echo "  $name = $value\n";
}

echo "\n=== Create instance ===\n";
$constructor = $rc->getConstructor();
echo "Has constructor: " . ($constructor ? 'yes' : 'no') . "\n";