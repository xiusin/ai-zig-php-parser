<?php
// f038 二分探针 b3_getsize：find 前仅注入一个候选调用
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
        echo str_repeat('  ', $indent) . "L {$this->name} ({$this->size}B)\n";
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
    public function getChildren(): array { return $this->children; }
    public function getName(): string { return $this->name; }
    public function getSize(): int {
        return array_sum(array_map(fn($c) => $c->getSize(), $this->children));
    }
    public function display(int $indent = 0): void {
        echo str_repeat('  ', $indent) . "C {$this->name} ({$this->getSize()}B)\n";
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
    public function find(string $name): ?Component { echo "F:" . $this->name . "?" . $name . "\n";
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
}

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

echo "Tot: " . $root->getSize() . "\n";
echo "--- Find only ---\n";
$found = $root->find('vendor');
echo "Found 'vendor': " . var_export($found !== null, true) . "\n";
if ($found) echo "  Size: " . $found->getSize() . "B\n";
echo "=== done ===\n";
