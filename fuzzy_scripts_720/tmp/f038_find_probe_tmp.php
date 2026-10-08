<?php
// f038 卡死最小复现探针：递归 find + foreach 体内 if-without-else + 早退
class Cmp { public function getName(): string { return 'x'; } }
class Node {
    public array $children = [];
    public function __construct(public string $name) {}
    public function getName(): string { return $this->name; }
    public function find(string $name): ?Node {
        if ($this->name === $name) return $this;
        foreach ($this->children as $child) {
            if ($child->getName() === $name) return $child;
            if ($child instanceof Node) {
                $found = $child->find($name);
                if ($found !== null) return $found;
            }
        }
        return null;
    }
}
$a = new Node('vendor');
$b = new Node('autoload');
$b->children = [$a];
$r = new Node('root');
$r->children = [$b, new Node('lib')];
var_dump($r->find('vendor') !== null);
var_dump($r->find('nope') === null);
echo "=== done ===\n";
