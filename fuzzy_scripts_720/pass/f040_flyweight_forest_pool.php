<?php
// 极度混搭: 享元模式 + 共享对象 + 内外部状态分离 + 对象池
echo "=== f040: Flyweight + Shared Objects + Pool ===\n";

class TreeType {
    public function __construct(
        public readonly string $name,
        public readonly string $color,
        public readonly string $texture
    ) {}

    public function draw(int $x, int $y, int $age): string {
        return sprintf("[%s tree at (%d,%d) age=%d color=%s]", $this->name, $x, $y, $age, $this->color);
    }
}

class TreeTypeFactory {
    private array $pool = [];

    public function get(string $name, string $color, string $texture): TreeType {
        $key = "$name:$color:$texture";
        if (!isset($this->pool[$key])) {
            $this->pool[$key] = new TreeType($name, $color, $texture);
        }
        return $this->pool[$key];
    }

    public function count(): int { return count($this->pool); }
    public function getTypes(): array { return array_keys($this->pool); }
}

class Tree {
    public function __construct(
        private TreeType $type,
        private int $x,
        private int $y,
        private int $age
    ) {}

    public function draw(): string { return $this->type->draw($this->x, $this->y, $this->age); }
    public function getType(): TreeType { return $this->type; }
}

class Forest {
    private array $trees = [];
    private TreeTypeFactory $factory;

    public function __construct() { $this->factory = new TreeTypeFactory(); }

    public function plantTree(string $name, string $color, string $texture, int $x, int $y, int $age): void {
        $type = $this->factory->get($name, $color, $texture);
        $this->trees[] = new Tree($type, $x, $y, $age);
    }

    public function draw(): void {
        foreach ($this->trees as $tree) {
            echo $tree->draw() . "\n";
        }
    }

    public function treeCount(): int { return count($this->trees); }
    public function typeCount(): int { return $this->factory->count(); }
    public function getTypes(): array { return $this->factory->getTypes(); }
}

// 测试
$forest = new Forest();

// 种很多树，但只有几种类型
$forest->plantTree('Oak', 'green', 'rough', 10, 20, 50);
$forest->plantTree('Oak', 'green', 'rough', 30, 40, 80);
$forest->plantTree('Oak', 'green', 'rough', 50, 60, 30);
$forest->plantTree('Pine', 'darkgreen', 'smooth', 70, 80, 20);
$forest->plantTree('Pine', 'darkgreen', 'smooth', 90, 10, 45);
$forest->plantTree('Birch', 'white', 'peeling', 15, 75, 15);
$forest->plantTree('Oak', 'green', 'rough', 25, 35, 60);
$forest->plantTree('Maple', 'red', 'smooth', 85, 55, 35);

echo "--- Forest ---\n";
$forest->draw();

echo "\nTrees: " . $forest->treeCount() . "\n";
echo "Unique types: " . $forest->typeCount() . "\n";
echo "Types: " . implode(', ', $forest->getTypes()) . "\n";

// 共享验证
echo "\n--- Shared Verification ---\n";
echo "8 trees but only " . $forest->typeCount() . " TreeType objects created (memory saved)\n";

echo "=== f040 Done ===\n";
