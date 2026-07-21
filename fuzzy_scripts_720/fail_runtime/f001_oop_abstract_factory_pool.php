<?php
// 极度混搭: 抽象工厂 + 对象池 + late static binding + 异常链 + 闭包回调
echo "=== f001: Abstract Factory + Object Pool + LSB + Exception Chain ===\n";

abstract class Animal {
    protected string $name;
    protected static int $count = 0;

    public function __construct(string $name) {
        $this->name = $name;
        static::$count++;
    }

    abstract public function speak(): string;
    abstract public function type(): string;

    public function getName(): string { return $this->name; }

    public static function getCount(): int { return static::$count; }

    public function describe(): string {
        return sprintf("[%s] %s says: %s", $this->type(), $this->name, $this->speak());
    }
}

class Dog extends Animal {
    public function speak(): string { return "Woof!"; }
    public function type(): string { return "Canine"; }
}

class Cat extends Animal {
    public function speak(): string { return "Meow~"; }
    public function type(): string { return "Feline"; }
}

class Bird extends Animal {
    public function speak(): string { return "Chirp!"; }
    public function type(): string { return "Avian"; }
}

abstract class AnimalFactory {
    abstract public function create(string $name): Animal;

    public static function getFactory(string $kind): AnimalFactory {
        return match($kind) {
            'dog' => new DogFactory(),
            'cat' => new CatFactory(),
            'bird' => new BirdFactory(),
            default => throw new InvalidArgumentException("Unknown animal: $kind"),
        };
    }
}

class DogFactory extends AnimalFactory {
    public function create(string $name): Animal { return new Dog($name); }
}
class CatFactory extends AnimalFactory {
    public function create(string $name): Animal { return new Cat($name); }
}
class BirdFactory extends AnimalFactory {
    public function create(string $name): Animal { return new Bird($name); }
}

class AnimalPool {
    private array $available = [];
    private array $inUse = [];
    private AnimalFactory $factory;

    public function __construct(AnimalFactory $factory) {
        $this->factory = $factory;
    }

    public function acquire(string $name): Animal {
        $key = get_class($this->factory) . ':' . $name;
        if (isset($this->available[$key])) {
            $animal = array_pop($this->available[$key]);
            if (empty($this->available[$key])) unset($this->available[$key]);
        } else {
            try {
                $animal = $this->factory->create($name);
            } catch (InvalidArgumentException $e) {
                throw new RuntimeException("Factory failed", 0, $e);
            }
        }
        $this->inUse[$key][] = $animal;
        return $animal;
    }

    public function release(string $name): void {
        $key = get_class($this->factory) . ':' . $name;
        if (!empty($this->inUse[$key])) {
            $animal = array_pop($this->inUse[$key]);
            if (empty($this->inUse[$key])) unset($this->inUse[$key]);
            $this->available[$key][] = $animal;
        }
    }

    public function stats(): array {
        $avail = 0; $used = 0;
        foreach ($this->available as $items) $avail += count($items);
        foreach ($this->inUse as $items) $used += count($items);
        return ['available' => $avail, 'inUse' => $used];
    }
}

// 测试
$pool = new AnimalPool(AnimalFactory::getFactory('dog'));
$d1 = $pool->acquire("Rex");
$d2 = $pool->acquire("Buddy");
echo $d1->describe() . "\n";
echo $d2->describe() . "\n";
echo "Stats: " . json_encode($pool->stats()) . "\n";

$pool->release("Rex");
echo "After release: " . json_encode($pool->stats()) . "\n";

$d3 = $pool->acquire("Rex");
echo "Re-acquired: " . $d3->describe() . "\n";

// 异常链测试
try {
    AnimalFactory::getFactory('unknown');
} catch (InvalidArgumentException $e) {
    echo "Caught: " . $e->getMessage() . "\n";
}

// 闭包回调批量创建
$factory = AnimalFactory::getFactory('cat');
$cats = array_map(fn($n) => $factory->create($n), ['Whiskers', 'Mittens', 'Tom']);
foreach ($cats as $cat) {
    echo $cat->describe() . "\n";
}

echo "Total animals: " . Animal::getCount() . "\n";
echo "=== f001 Done ===\n";
