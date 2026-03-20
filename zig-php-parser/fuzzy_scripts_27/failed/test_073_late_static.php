<?php
// Test 073: Late static binding
class LateStaticBase {
    protected static string $name = 'Base';

    public static function getName(): string {
        return static::$name;
    }

    public static function setName(string $name): void {
        static::$name = $name;
    }

    public static function create(): static {
        return new static();
    }
}

class LateStaticChild extends LateStaticBase {
    protected static string $name = 'Child';
}

class LateStaticGrandChild extends LateStaticChild {
    protected static string $name = 'GrandChild';
}

echo "=== Late static binding ===\n";
echo "LateStaticBase::getName(): " . LateStaticBase::getName() . "\n";
echo "LateStaticChild::getName(): " . LateStaticChild::getName() . "\n";
echo "LateStaticGrandChild::getName(): " . LateStaticGrandChild::getName() . "\n";

echo "\n=== create() ===\n";
echo "LateStaticBase::create() class: " . get_class(LateStaticBase::create()) . "\n";
echo "LateStaticChild::create() class: " . get_class(LateStaticChild::create()) . "\n";
echo "LateStaticGrandChild::create() class: " . get_class(LateStaticGrandChild::create()) . "\n";

echo "\n=== setName mutation ===\n";
LateStaticBase::setName('ModifiedBase');
LateStaticChild::setName('ModifiedChild');
LateStaticGrandChild::setName('ModifiedGrand');

echo "After setName:\n";
echo "  LateStaticBase::getName(): " . LateStaticBase::getName() . "\n";
echo "  LateStaticChild::getName(): " . LateStaticChild::getName() . "\n";
echo "  LateStaticGrandChild::getName(): " . LateStaticGrandChild::getName() . "\n";