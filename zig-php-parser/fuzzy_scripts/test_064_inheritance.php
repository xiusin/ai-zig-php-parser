<?php
// Test 064: Class inheritance, parent, protected, private
class ParentClass {
    protected string $protected = 'parent_protected';
    private string $private = 'parent_private';

    protected function protectedMethod(): string {
        return "parent protected method";
    }

    private function privateMethod(): string {
        return "parent private method";
    }

    public function callProtected(): string {
        return $this->protectedMethod();
    }

    public function callPrivate(): string {
        return $this->privateMethod();
    }

    public function getProtected(): string {
        return $this->protected;
    }

    public function getPrivate(): string {
        return $this->private;
    }
}

class ChildClass extends ParentClass {
    protected string $protected = 'child_protected';
    private string $private = 'child_private';

    protected function protectedMethod(): string {
        return "child protected method";
    }

    private function privateMethod(): string {
        return "child private method";
    }

    public function getParentProtected(): string {
        return parent::getProtected();
    }

    public function getParentPrivate(): string {
        return parent::getPrivate();
    }

    public function getParentMethod(): string {
        return parent::callProtected();
    }
}

echo "=== Inheritance visibility ===\n";
$child = new ChildClass();

echo "child->getProtected(): " . $child->getProtected() . "\n";
echo "child->getParentProtected(): " . $child->getParentProtected() . "\n";

echo "child->callProtected(): " . $child->callProtected() . "\n";
echo "child->getParentMethod(): " . $child->getParentMethod() . "\n";

echo "\n=== Private in parent vs child ===\n";
echo "child->getPrivate(): " . $child->getPrivate() . "\n";
echo "child->getParentPrivate(): " . $child->getParentPrivate() . "\n";

echo "child->callPrivate(): " . $child->callPrivate() . "\n";

echo "\n=== Method resolution ===\n";
class A {
    public function greet(): string {
        return "Hello from A";
    }
}

class B extends A {
    public function greet(): string {
        return "Hello from B";
    }

    public function greetParent(): string {
        return parent::greet();
    }
}

$b = new B();
echo "b->greet(): " . $b->greet() . "\n";
echo "b->greetParent(): " . $b->greetParent() . "\n";

echo "\n=== Static in inheritance ===\n";
class StaticParent {
    protected static string $value = 'parent_static';

    public static function get(): string {
        return static::$value;
    }
}

class StaticChild extends StaticParent {
    protected static string $value = 'child_static';
}

echo "StaticParent::get(): " . StaticParent::get() . "\n";
echo "StaticChild::get(): " . StaticChild::get() . "\n";