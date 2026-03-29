<?php
// Test 135: Static property inheritance
class StaticInheritBase {
    protected static array $items = [];

    public static function add(string $item): void {
        self::$items[] = $item;
    }

    public static function getAll(): array {
        return self::$items;
    }

    public static function count(): int {
        return count(self::$items);
    }
}

class StaticInheritChild extends StaticInheritBase {
    protected static array $items = [];
}

class StaticInheritGrandchild extends StaticInheritChild {}

echo "=== Static property inheritance ===\n";
StaticInheritBase::add('base_item');
StaticInheritChild::add('child_item');
StaticInheritGrandchild::add('grandchild_item');

echo "Base items: " . implode(', ', StaticInheritBase::getAll()) . "\n";
echo "Child items: " . implode(', ', StaticInheritChild::getAll()) . "\n";
echo "Grandchild items: " . implode(', ', StaticInheritGrandchild::getAll()) . "\n";

echo "\n=== Static counts ===\n";
echo "Base count: " . StaticInheritBase::count() . "\n";
echo "Child count: " . StaticInheritChild::count() . "\n";
echo "Grandchild count: " . StaticInheritGrandchild::count() . "\n";