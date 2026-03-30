<?php
// Test 011: Reflection API deep usage
class ReflectLab {
    private string $prop = 'private_value';
    protected int $num = 42;
    public array $data = [1, 2, 3];

    public function method(string $a, int $b = 10): string {
        return "Called with $a and $b";
    }

    private function privateMethod(): string {
        return "private";
    }

    static function staticMethod(): string {
        return "static";
    }
}

interface TestInterface {
    public function interfaceMethod(): int;
}

abstract class AbstractClass {
    abstract public function abstractMethod(): void;
}

class ConcreteClass extends AbstractClass implements TestInterface {
    public const CONSTANT = 42;

    public function __construct(
        private readonly string $value,
        private int $number = 0
    ) {}

    public function interfaceMethod(): int {
        return $this->number;
    }

    public function abstractMethod(): void {
        echo "Implemented\n";
    }

    public function __toString(): string {
        return "ConcreteClass($this->value)";
    }
}

$out = "";

// Class reflection
$rc = new ReflectionClass(ReflectLab::class);
$out .= "Class name: " . $rc->getName() . "\n";
$out .= "Is class: " . ($rc->isClass() ? 'yes' : 'no') . "\n";
$out .= "Is interface: " . ($rc->isInterface() ? 'yes' : 'no') . "\n";
$out .= "Is abstract: " . ($rc->isAbstract() ? 'yes' : 'no') . "\n";
$out .= "Is final: " . ($rc->isFinal() ? 'yes' : 'no') . "\n";
$out .= "Is instantiable: " . ($rc->isInstantiable() ? 'yes' : 'no') . "\n";

// Properties
$out .= "\nProperties:\n";
foreach ($rc->getProperties() as $prop) {
    $out .= "  {$prop->getName()}: " . ($prop->isPrivate() ? 'private' : ($prop->isProtected() ? 'protected' : 'public')) . "\n";
}

// Methods
$out .= "\nMethods:\n";
foreach ($rc->getMethods() as $method) {
    $out .= "  {$method->getName()}() - " . ($method->isPublic() ? 'public' : ($method->isProtected() ? 'protected' : 'private'));
    $out .= ($method->isStatic() ? ' static' : '');
    $out .= ($method->isAbstract() ? ' abstract' : '');
    $out .= "\n";
}

// Method invocation via reflection
$obj = new ReflectLab();
$rm = new ReflectionMethod($obj, 'method');
$out .= "\nInvoke method: " . $rm->invoke($obj, 'test', 20) . "\n";

// Property access
$rp = new ReflectionProperty($obj, 'prop');
$rp->setAccessible(true);
$out .= "Get private prop: " . $rp->getValue($obj) . "\n";

// Parameter reflection
$params = $rm->getParameters();
$out .= "Method parameters:\n";
foreach ($params as $param) {
    $out .= "  {$param->getName()}: " . ($param->isOptional() ? 'optional' : 'required');
    if ($param->isDefaultAvailable()) {
        $out .= " = " . var_export($param->getDefaultValue(), true);
    }
    $out .= "\n";
}

// Interface implementation check
$cc = new ReflectionClass(ConcreteClass::class);
$out .= "\nImplements TestInterface: " . ($cc->implementsInterface(TestInterface::class) ? 'yes' : 'no') . "\n";

// Extension check
$re = new ReflectionExtension('standard');
$out .= "Standard extension version: " . $re->getVersion() . "\n";
$out .= "Standard extension classes: " . count($re->getClasses()) . "\n";
$out .= "Standard extension functions: " . count($re->getFunctions()) . "\n";

// ReflectionParameter
$rm2 = new ReflectionMethod($obj, 'method');
$param = $rm2->getParameters()[0];
$out .= "\nParameter {$param->getName()}:\n";
$out .= "  Position: " . $param->getPosition() . "\n";
$out .= "  Type: " . ($param->getType() ? $param->getType()->getName() : 'none') . "\n";
$out .= "  Allows null: " . ($param->allowsNull() ? 'yes' : 'no') . "\n";

echo $out;