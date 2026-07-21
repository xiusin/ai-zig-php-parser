<?php
// 极度混搭: 组合模式 + 树形结构 + 统一接口 + 递归操作 + 计算属性
echo "=== f038: Composite + Tree Structure + Recursive Ops ===\n";

interface Component {
    public function getName(): string;
    public function getSize(): int;
    public function display(int $indent = 0): void;
    public function toArray(): array;
}

class Leaf implements Component {
    public function __construct(private string $name, private int $size) {}

    public function getName(): string { return $this->name; }
    public function getSize(): int { return $this->size; }

    public function display(int $indent = 0): void {
        echo str_repeat('  ', $indent) . "📄 {$this->name} ({$this->size}B)\n";
    }

    public function toArray(): array {
        return ['type' => 'leaf', 'name' => $this->name, 'size' => $this->size];
    }
}

class Composite implements Component {
    private array $children = [];

    public function __construct(private string $name) {}

    public function add(Component $component): self {
        $this->children[] = $component;
        return $this;
    }

    public function remove(Component $component): self {
        $this->children = array_filter($this->children, fn($c) => $c !== $component);
        $this->children = array_values($this->children);
        return $this;
    }

    public function getChildren(): array { return $this->children; }
    public function getName(): string { return $this->name; }

    public function getSize(): int {
        return array_sum(array_map(fn($c) => $c->getSize(), $this->children));
    }

    public function display(int $indent = 0): void {
        echo str_repeat('  ', $indent) . "📁 {$this->name} ({$this->getSize()}B)\n";
        foreach ($this->children as $child) {
            $child->display($indent + 1);
        }
    }

    public function toArray(): array {
        return [
            'type' => 'composite',
            'name' => $this->name,
            'size' => $this->getSize(),
            'children' => array_map(fn($c) => $c->toArray(), $this->children),
        ];
    }

    public function find(string $name): ?Component {
        if ($this->name === $name) return $this;
        foreach ($this->children as $child) {
            if ($child->getName() === $name) return $child;
            if ($child instanceof Composite) {
                $found = $child->find($name);
                if ($found !== null) return $found;
            }
        }
        return null;
    }

    public function countLeaves(): int {
        $count = 0;
        foreach ($this->children as $child) {
            if ($child instanceof Leaf) $count++;
            elseif ($child instanceof Composite) $count += $child->countLeaves();
        }
        return $count;
    }

    public function maxDepth(): int {
        $max = 0;
        foreach ($this->children as $child) {
            $depth = $child instanceof Composite ? $child->maxDepth() + 1 : 1;
            if ($depth > $max) $max = $depth;
        }
        return $max;
    }
}

// 构建文件系统
$root = new Composite('root');
$src = new Composite('src');
$src->add(new Leaf('main.php', 1024))
    ->add(new Leaf('config.php', 512))
    ->add(new Leaf('utils.php', 2048));

$lib = new Composite('lib');
$lib->add(new Leaf('helpers.php', 768));
$vendor = new Composite('vendor');
$vendor->add(new Leaf('autoload.php', 256))
       ->add(new Leaf('composer.php', 384));
$lib->add($vendor);

$root->add($src)->add($lib)->add(new Leaf('README.md', 128));

// 显示
echo "--- File System ---\n";
$root->display();

// 统计
echo "\nTotal size: " . $root->getSize() . "B\n";
echo "Total leaves: " . $root->countLeaves() . "\n";
echo "Max depth: " . $root->maxDepth() . "\n";

// 查找
echo "\n--- Find ---\n";
$found = $root->find('vendor');
echo "Found 'vendor': " . var_export($found !== null, true) . "\n";
if ($found) echo "  Size: " . $found->getSize() . "B\n";

$found2 = $root->find('main.php');
echo "Found 'main.php': " . var_export($found2 !== null, true) . "\n";
if ($found2) echo "  Size: " . $found2->getSize() . "B\n";

$notFound = $root->find('nonexistent');
echo "Found 'nonexistent': " . var_export($notFound !== null, true) . "\n";

// JSON
echo "\n--- JSON ---\n";
echo json_encode($root->toArray()) . "\n";

// 删除
echo "\n--- After removing utils.php from src ---\n";
$utils = $src->find('utils.php');
if ($utils) $src->remove($utils);
$src->display(1);
echo "New total: " . $root->getSize() . "B\n";

echo "=== f038 Done ===\n";
