<?php
// f038 探针2：递归中 $this 与 foreach 迭代器是否错乱
interface Comp { public function getName(): string; public function find(string $n): ?Comp; }
class Leaf implements Comp {
    public function __construct(private string $name) {}
    public function getName(): string { return $this->name; }
    public function find(string $n): ?Comp { return $this->name === $n ? $this : null; }
}
class Comp2 implements Comp {
    private array $children = [];
    public function __construct(private string $name) {}
    public function add(Comp $c): self { $this->children[] = $c; return $this; }
    public function getName(): string { return $this->name; }
    public function find(string $n): ?Comp {
        echo "enter:" . $this->name . "\n";
        if ($this->name === $n) return $this;
        foreach ($this->children as $child) {
            if ($child->getName() === $n) return $child;
            if ($child instanceof Comp2) {
                $found = $child->find($n);
                if ($found !== null) return $found;
            }
        }
        return null;
    }
}
$src = new Comp2('src');
$src->add(new Leaf('main.php'))->add(new Leaf('cfg.php'));
$lib = new Comp2('lib');
$root = new Comp2('root');
$root->add($src)->add($lib)->add(new Leaf('README'));
var_dump($root->find('main.php') !== null);
echo "=== done ===\n";
