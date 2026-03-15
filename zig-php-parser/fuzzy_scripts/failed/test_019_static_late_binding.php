<?php
// 测试19: 静态绑定与后期静态绑定
class ParentClass {
    protected static string $name = "Parent";
    
    public static function getName(): string {
        return self::$name;
    }
    
    public static function getNameLate(): string {
        return static::$name;
    }
    
    public static function create(): static {
        return new static();
    }
}

class ChildClass extends ParentClass {
    protected static string $name = "Child";
}

class GrandChildClass extends ChildClass {
    protected static string $name = "GrandChild";
}

// 测试self vs static
echo "Parent::getName(): " . ParentClass::getName() . "\n";
echo "Child::getName(): " . ChildClass::getName() . "\n";
echo "GrandChild::getName(): " . GrandChildClass::getName() . "\n";

echo "\nUsing static::\n";
echo "Parent::getNameLate(): " . ParentClass::getNameLate() . "\n";
echo "Child::getNameLate(): " . ChildClass::getNameLate() . "\n";
echo "GrandChild::getNameLate(): " . GrandChildClass::getNameLate() . "\n";

// 测试工厂模式
echo "\nFactory pattern:\n";
$parent = ParentClass::create();
$child = ChildClass::create();
$grandChild = GrandChildClass::create();

echo "Parent create: " . get_class($parent) . "\n";
echo "Child create: " . get_class($child) . "\n";
echo "GrandChild create: " . get_class($grandChild) . "\n";

// 复杂静态调用链
class StaticChain {
    private static int $counter = 0;
    
    public static function increment(): int {
        return ++self::$counter;
    }
    
    public static function getCount(): int {
        return self::$counter;
    }
    
    public static function chain(): string {
        return static::class . ":" . static::increment();
    }
}

class StaticChainChild extends StaticChain {}

echo "\nStatic chain:\n";
echo StaticChain::chain() . "\n";
echo StaticChainChild::chain() . "\n";
echo StaticChain::chain() . "\n";
?>
