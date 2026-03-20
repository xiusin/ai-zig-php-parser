<?php
// Test 055: Static methods, late static binding, and self/parent
class StaticBase {
    protected static string $name = 'StaticBase';
    public static function getName(): string {
        return self::$name;
    }
    public static function getNameLate(): string {
        return static::$name;
    }
    public static function setName(string $name): void {
        static::$name = $name;
    }
}

class StaticDerived extends StaticBase {
    protected static string $name = 'StaticDerived';
}

class StaticGrandChild extends StaticDerived {
    protected static string $name = 'StaticGrandChild';
}

echo "=== Static method binding ===\n";
echo "StaticBase::getName(): " . StaticBase::getName() . "\n";
echo "StaticBase::getNameLate(): " . StaticBase::getNameLate() . "\n";
echo "StaticDerived::getName(): " . StaticDerived::getName() . "\n";
echo "StaticDerived::getNameLate(): " . StaticDerived::getNameLate() . "\n";
echo "StaticGrandChild::getName(): " . StaticGrandChild::getName() . "\n";
echo "StaticGrandChild::getNameLate(): " . StaticGrandChild::getNameLate() . "\n";

echo "\n=== Static property mutation ===\n";
StaticBase::setName('ModifiedBase');
echo "After setName('ModifiedBase'):\n";
echo "  StaticBase::getNameLate(): " . StaticBase::getNameLate() . "\n";
echo "  StaticDerived::getNameLate(): " . StaticDerived::getNameLate() . "\n";
echo "  StaticGrandChild::getNameLate(): " . StaticGrandChild::getNameLate() . "\n";

echo "\n=== Static constant vs property ===\n";
class StaticConst {
    public const VALUE = 'const';
    public static string $prop = 'prop';

    public function getSelf(): string {
        return self::VALUE . ' ' . self::$prop;
    }

    public function getStatic(): string {
        return static::VALUE . ' ' . static::$prop;
    }
}

class ChildStaticConst extends StaticConst {
    public const VALUE = 'child_const';
    public static string $prop = 'child_prop';
}

$obj = new StaticConst();
$child = new ChildStaticConst();
echo "StaticConst getSelf(): " . $obj->getSelf() . "\n";
echo "StaticConst getStatic(): " . $obj->getStatic() . "\n";
echo "ChildStaticConst getSelf(): " . $child->getSelf() . "\n";
echo "ChildStaticConst getStatic(): " . $child->getStatic() . "\n";

echo "\n=== Static in closure ===\n";
class StaticClosure {
    public static string $value = 'static_value';

    public function getClosure(): callable {
        return function(): string {
            return static::$value;
        };
    }
}

$sc = new StaticClosure();
$fn = $sc->getClosure();
echo "StaticClosure fn(): " . $fn() . "\n";