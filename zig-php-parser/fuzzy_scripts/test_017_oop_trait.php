<?php
// OOP Trait测试

// 基础Trait
trait LoggerTrait {
    protected function log(string $message): void {
        echo "[LOG] $message\n";
    }
}

trait TimestampTrait {
    protected function getTimestamp(): string {
        return date('Y-m-d H:i:s');
    }
}

// 使用Trait
class Service {
    use LoggerTrait;
    use TimestampTrait;

    public function doSomething(): void {
        $this->log("Doing something at " . $this->getTimestamp());
    }
}

$service = new Service();
$service->doSomething();

// 多个Trait一起使用
class MultiTraitClass {
    use LoggerTrait, TimestampTrait;

    public function run(): void {
        $this->log("Running...");
    }
}

$multi = new MultiTraitClass();
$multi->run();

// Trait冲突解决
trait A {
    public function conflict(): string {
        return "A";
    }
}

trait B {
    public function conflict(): string {
        return "B";
    }
}

class ConflictResolution {
    use A, B {
        A::conflict insteadof B;
        B::conflict as conflictB;
    }
}

$resolver = new ConflictResolution();
echo "conflict from A: " . $resolver->conflict() . "\n";
echo "conflict from B: " . $resolver->conflictB() . "\n";

// Trait方法可见性修改
trait PrivateTrait {
    private function secret(): string {
        return "secret";
    }

    protected function internal(): string {
        return "internal";
    }
}

class PublicTrait {
    use PrivateTrait {
        secret as public;
        internal as public;
    }
}

$public = new PublicTrait();
echo "now public: " . $public->secret() . "\n";
echo "also public: " . $public->internal() . "\n";

// Trait属性
trait PropertyTrait {
    protected string $traitProperty = 'trait value';

    public function getTraitProperty(): string {
        return $this->traitProperty;
    }

    public function setTraitProperty(string $value): void {
        $this->traitProperty = $value;
    }
}

class UsingPropertyTrait {
    use PropertyTrait;
}

$prop = new UsingPropertyTrait();
echo "Trait property: " . $prop->getTraitProperty() . "\n";
$prop->setTraitProperty('modified');
echo "Modified: " . $prop->getTraitProperty() . "\n";

// 抽象Trait方法
trait AbstractTrait {
    abstract protected function getValue(): string;

    public function display(): void {
        echo "Value: " . $this->getValue() . "\n";
    }
}

class UsingAbstractTrait {
    use AbstractTrait;

    protected function getValue(): string {
        return "concrete value";
    }
}

$abstract = new UsingAbstractTrait();
$abstract->display();

// 静态Trait方法
trait StaticTrait {
    private static int $counter = 0;

    public static function increment(): int {
        return ++self::$counter;
    }

    public static function getCount(): int {
        return self::$counter;
    }
}

class UsingStaticTrait {
    use StaticTrait;
}

echo "Counter: " . UsingStaticTrait::increment() . "\n";
echo "Counter: " . UsingStaticTrait::increment() . "\n";
echo "Total: " . UsingStaticTrait::getCount() . "\n";

// Trait嵌套
trait NestedTrait {
    use LoggerTrait;

    public function nested(): void {
        $this->log("Nested trait call");
    }
}

class UsingNestedTrait {
    use NestedTrait;
}

$nested = new UsingNestedTrait();
$nested->nested();
