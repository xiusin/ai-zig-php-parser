<?php
// Test 040: Class constant visibility, interface default values, and abstract classes
abstract class AbstractBase {
    abstract public function abstractMethod(): string;
    public function concreteMethod(): string {
        return "Concrete implementation";
    }
    public static function staticMethod(): string {
        return "Static in abstract";
    }
}

interface BaseInterface {
    public const INTERFACE_CONST = 'interface_value';

    public function interfaceMethod(): string;
}

interface ExtendedInterface extends BaseInterface {
    public const EXTENDED_CONST = 'extended_value';

    public function extendedMethod(): string;
}

trait BaseTrait {
    public const TRAIT_CONST = 'trait_value';

    public function traitMethod(): string {
        return "Trait method";
    }
}

class ConcreteClass extends AbstractBase implements BaseInterface, ExtendedInterface {
    use BaseTrait;

    public const CLASS_CONST = 'class_value';

    public function abstractMethod(): string {
        return "Implemented abstract";
    }

    public function interfaceMethod(): string {
        return "Implemented interface";
    }

    public function extendedMethod(): string {
        return "Implemented extended";
    }
}

class ChildClass extends ConcreteClass {
    public function getParentConstant(): string {
        return parent::CLASS_CONST;
    }
}

echo "=== Abstract class ===\n";
$obj = new ConcreteClass();
echo "abstractMethod: " . $obj->abstractMethod() . "\n";
echo "concreteMethod: " . $obj->concreteMethod() . "\n";
echo "staticMethod: " . AbstractBase::staticMethod() . "\n";

echo "\n=== Interface ===\n";
echo "INTERFACE_CONST: " . BaseInterface::INTERFACE_CONST . "\n";
echo "interfaceMethod: " . $obj->interfaceMethod() . "\n";

echo "\n=== Extended interface ===\n";
echo "EXTENDED_CONST: " . ExtendedInterface::EXTENDED_CONST . "\n";
echo "extendedMethod: " . $obj->extendedMethod() . "\n";

echo "\n=== Trait ===\n";
echo "TRAIT_CONST: " . ConcreteClass::TRAIT_CONST . "\n";
echo "traitMethod: " . $obj->traitMethod() . "\n";

echo "\n=== Class constant visibility ===\n";
echo "CLASS_CONST: " . ConcreteClass::CLASS_CONST . "\n";
$child = new ChildClass();
echo "ChildClass getParentConstant: " . $child->getParentConstant() . "\n";

echo "\n=== Interface default method via abstract class ===\n";
abstract class InterfaceWithDefault {
    public function defaultMethod(): string {
        return "Default via abstract class";
    }
    abstract public function interfaceMethod(): string;
}

class ImplementWithDefaults extends InterfaceWithDefault {
    public function interfaceMethod(): string {
        return "Custom implementation";
    }
}

$impl = new ImplementWithDefaults();
echo "defaultMethod from abstract: " . $impl->defaultMethod() . "\n";

echo "\n=== Reflection on constants ===\n";
$rc = new ReflectionClass(ConcreteClass::class);
$consts = $rc->getConstants();
echo "ConcreteClass constants: " . implode(', ', array_keys($consts)) . "\n";

$iface = new ReflectionClass(BaseInterface::class);
$ifaceConsts = $iface->getConstants();
echo "BaseInterface constants: " . implode(', ', $ifaceConsts) . "\n";