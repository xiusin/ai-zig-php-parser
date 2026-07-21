<?php
// 极度混搭: JSON编解码 + 树形结构 + 递归遍历 + 路径查找 + 序列化
echo "=== f012: JSON Tree + Recursive Traverse + Path Find ===\n";

class TreeNode {
    public array $children = [];

    public function __construct(
        public string $name,
        public mixed $data = null
    ) {}

    public function addChild(TreeNode $child): TreeNode {
        $this->children[] = $child;
        return $child;
    }

    public function isLeaf(): bool {
        return empty($this->children);
    }

    public function depth(): int {
        if ($this->isLeaf()) return 1;
        $maxChildDepth = 0;
        foreach ($this->children as $child) {
            $d = $child->depth();
            if ($d > $maxChildDepth) $maxChildDepth = $d;
        }
        return $maxChildDepth + 1;
    }

    public function countNodes(): int {
        $count = 1;
        foreach ($this->children as $child) {
            $count += $child->countNodes();
        }
        return $count;
    }

    public function find(string $name): ?TreeNode {
        if ($this->name === $name) return $this;
        foreach ($this->children as $child) {
            $found = $child->find($name);
            if ($found !== null) return $found;
        }
        return null;
    }

    public function pathTo(string $name): ?array {
        if ($this->name === $name) return [$this->name];
        foreach ($this->children as $child) {
            $path = $child->pathTo($name);
            if ($path !== null) return array_merge([$this->name], $path);
        }
        return null;
    }

    public function flatten(): array {
        $result = [['name' => $this->name, 'depth' => 0, 'data' => $this->data]];
        foreach ($this->children as $child) {
            foreach ($child->flatten() as $item) {
                $item['depth']++;
                $result[] = $item;
            }
        }
        return $result;
    }

    public function toJSON(): string {
        return json_encode($this->toArray());
    }

    public function toArray(): array {
        $children = array_map(fn($c) => $c->toArray(), $this->children);
        return ['name' => $this->name, 'data' => $this->data, 'children' => $children];
    }

    public static function fromArray(array $arr): TreeNode {
        $node = new TreeNode($arr['name'], $arr['data'] ?? null);
        foreach ($arr['children'] ?? [] as $childArr) {
            $node->addChild(self::fromArray($childArr));
        }
        return $node;
    }

    public function print(string $indent = ''): void {
        echo $indent . $this->name;
        if ($this->data !== null) echo " (" . json_encode($this->data) . ")";
        echo "\n";
        foreach ($this->children as $child) {
            $child->print($indent . '  ');
        }
    }
}

// 构建树
$root = new TreeNode('root', ['type' => 'dir']);
$src = $root->addChild(new TreeNode('src', ['type' => 'dir']));
$src->addChild(new TreeNode('main.php', ['type' => 'file', 'size' => 1024]));
$src->addChild(new TreeNode('config.php', ['type' => 'file', 'size' => 512]));

$lib = $root->addChild(new TreeNode('lib', ['type' => 'dir']));
$lib->addChild(new TreeNode('utils.php', ['type' => 'file', 'size' => 2048]));
$vendor = $lib->addChild(new TreeNode('vendor', ['type' => 'dir']));
$vendor->addChild(new TreeNode('autoload.php', ['type' => 'file', 'size' => 256]));

$root->addChild(new TreeNode('README.md', ['type' => 'file', 'size' => 128]));

// 打印树
echo "Tree structure:\n";
$root->print();

// 统计
echo "\nTotal nodes: " . $root->countNodes() . "\n";
echo "Max depth: " . $root->depth() . "\n";

// 查找
$found = $root->find('utils.php');
echo "Found 'utils.php': " . var_export($found !== null, true) . "\n";
if ($found) echo "  data: " . json_encode($found->data) . "\n";

$notFound = $root->find('nonexistent');
echo "Found 'nonexistent': " . var_export($notFound !== null, true) . "\n";

// 路径
$path = $root->pathTo('autoload.php');
echo "Path to 'autoload.php': " . implode(' -> ', $path ?? []) . "\n";

$path2 = $root->pathTo('README.md');
echo "Path to 'README.md': " . implode(' -> ', $path2 ?? []) . "\n";

// 扁平化
echo "\nFlattened:\n";
foreach ($root->flatten() as $item) {
    echo str_repeat('  ', $item['depth']) . $item['name'] . "\n";
}

// JSON 序列化/反序列化
$json = $root->toJSON();
echo "\nJSON: " . substr($json, 0, 100) . "...\n";

$restored = TreeNode::fromArray(json_decode($json, true));
echo "Restored nodes: " . $restored->countNodes() . "\n";
echo "Restored depth: " . $restored->depth() . "\n";
echo "Restored find 'main.php': " . var_export($restored->find('main.php') !== null, true) . "\n";

echo "=== f012 Done ===\n";
