<?php
// Test 098: Abstract class and methods
abstract class AbstractBase {
    abstract public function abstractMethod(): string;

    public function concreteMethod(): string {
        return "concrete";
    }

    protected abstract function protectedAbstract(): string;

    public function callProtectedAbstract(): string {
        return $this->protectedAbstract();
    }
}

class ConcreteImpl extends AbstractBase {
    public function abstractMethod(): string {
        return "implemented";
    }

    protected function protectedAbstract(): string {
        return "protected_implemented";
    }
}

abstract class AbstractChild extends AbstractBase {
    abstract public function additionalAbstract(): int;
}

class FullImpl extends AbstractChild {
    public function abstractMethod(): string {
        return "abstract_method";
    }

    protected function protectedAbstract(): string {
        return "protected_method";
    }

    public function additionalAbstract(): int {
        return 42;
    }
}

echo "=== Abstract class ===\n";
$impl = new ConcreteImpl();
echo "abstractMethod: " . $impl->abstractMethod() . "\n";
echo "concreteMethod: " . $impl->concreteMethod() . "\n";
echo "callProtectedAbstract: " . $impl->callProtectedAbstract() . "\n";

echo "\n=== Full implementation ===\n";
$full = new FullImpl();
echo "abstractMethod: " . $full->abstractMethod() . "\n";
echo "additionalAbstract: " . $full->additionalAbstract() . "\n";

echo "\n=== Abstract with no additional ===\n";
echo "FullImpl instance count: 1\n";