<?php
// Test 042: Static vs instance properties, late static binding
class StaticBase {
    public static int $staticCount = 0;
    public int $instanceCount = 0;

    public function __construct() {
        $this->instanceCount = ++self::$staticCount;
    }

    public static function getStaticCount(): int {
        return self::$staticCount;
    }

    public static function resetStatic(): void {
        self::$staticCount = 0;
    }
}

class StaticChild extends StaticBase {
    public static string $staticName = 'Child';

    public static function getStaticName(): string {
        return self::$staticName;
    }

    public static function getStaticNameLate(): string {
        return static::$staticName;
    }
}

class LateStaticBinding {
    public static function getClassName(): string {
        return static::class;
    }

    public static function create(): static {
        return new static();
    }

    public static int $count = 0;
}

class ChildLateStatic extends LateStaticBinding {}

echo "=== Static vs Instance ===\n";
$obj1 = new StaticBase();
$obj2 = new StaticBase();
$child1 = new StaticChild();
$child2 = new StaticChild();

echo "StaticBase::staticCount: " . StaticBase::$staticCount . "\n";
echo "StaticChild::staticCount: " . StaticChild::$staticCount . "\n";
echo "obj1 instanceCount: " . $obj1->instanceCount . "\n";
echo "obj2 instanceCount: " . $obj2->instanceCount . "\n";
echo "child1 instanceCount: " . $child1->instanceCount . "\n";

echo "\n=== Static Name Binding ===\n";
echo "StaticChild::getStaticName(): " . StaticChild::getStaticName() . "\n";
echo "StaticChild::getStaticNameLate(): " . StaticChild::getStaticNameLate() . "\n";

echo "\n=== Late Static Binding ===\n";
echo "LateStaticBinding::getClassName(): " . LateStaticBinding::getClassName() . "\n";
echo "ChildLateStatic::getClassName(): " . ChildLateStatic::getClassName() . "\n";

$late1 = LateStaticBinding::create();
echo "LateStaticBinding::create() class: " . get_class($late1) . "\n";
$late2 = ChildLateStatic::create();
echo "ChildLateStatic::create() class: " . get_class($late2) . "\n";

echo "\n=== Static property inheritance ===\n";
StaticBase::resetStatic();
echo "After reset, count: " . StaticBase::$staticCount . "\n";

$base1 = new StaticBase();
$base2 = new StaticBase();
$childA = new StaticChild();
$childB = new StaticChild();

echo "Total StaticBase count: " . StaticBase::$staticCount . "\n";
echo "Total StaticChild count: " . StaticChild::$staticCount . "\n";

echo "\n=== Static constants vs properties ===\n";
class StaticConstants {
    public const CONST_VALUE = 'const';
    public static string $propValue = 'prop';

    public function getConst(): string {
        return self::CONST_VALUE;
    }

    public function getProp(): string {
        return self::$propValue;
    }

    public function getConstLate(): string {
        return static::CONST_VALUE;
    }

    public function getPropLate(): string {
        return static::$propValue;
    }
}

class ChildStaticConstants extends StaticConstants {
    public const CONST_VALUE = 'child_const';
    public static string $propValue = 'child_prop';
}

$base = new StaticConstants();
$child = new ChildStaticConstants();
echo "Base getConst: " . $base->getConst() . "\n";
echo "Base getProp: " . $base->getProp() . "\n";
echo "Base getConstLate: " . $base->getConstLate() . "\n";
echo "Base getPropLate: " . $base->getPropLate() . "\n";
echo "Child getConst: " . $child->getConst() . "\n";
echo "Child getProp: " . $child->getProp() . "\n";
echo "Child getConstLate: " . $child->getConstLate() . "\n";
echo "Child getPropLate: " . $child->getPropLate() . "\n";