<?php
// 极度混搭: 红黑树性质验证 + 布隆过滤器 + 跳表删除 + 一致性哈希
echo "=== c033: RedBlack Verify + BloomFilter + ConsistentHash ===\n\n";

class RBTreeNode {
    public int $value;
    public bool $red = true;
    public ?RBTreeNode $left = null;
    public ?RBTreeNode $right = null;
    public ?RBTreeNode $parent = null;

    public function __construct(int $value) {
        $this->value = $value;
    }
}

class RedBlackTree {
    private ?RBTreeNode $root = null;
    private int $size = 0;

    public function insert(int $value): void {
        $node = new RBTreeNode($value);
        $this->size++;

        if ($this->root === null) {
            $this->root = $node;
            $node->red = false;
            return;
        }

        $current = $this->root;
        while (true) {
            if ($value < $current->value) {
                if ($current->left === null) {
                    $current->left = $node;
                    $node->parent = $current;
                    break;
                }
                $current = $current->left;
            } else {
                if ($current->right === null) {
                    $current->right = $node;
                    $node->parent = $current;
                    break;
                }
                $current = $current->right;
            }
        }

        $this->fixInsert($node);
    }

    private function fixInsert(RBTreeNode $node): void {
        while ($node->parent !== null && $node->parent->red) {
            $parent = $node->parent;
            $grandparent = $parent->parent;
            if ($grandparent === null) break;

            if ($parent === $grandparent->left) {
                $uncle = $grandparent->right;
                if ($uncle !== null && $uncle->red) {
                    $parent->red = false;
                    $uncle->red = false;
                    $grandparent->red = true;
                    $node = $grandparent;
                } else {
                    if ($node === $parent->right) {
                        $node = $parent;
                        $this->rotateLeft($node);
                    }
                    $node->parent->red = false;
                    $node->parent->parent->red = true;
                    $this->rotateRight($node->parent->parent);
                }
            } else {
                $uncle = $grandparent->left;
                if ($uncle !== null && $uncle->red) {
                    $parent->red = false;
                    $uncle->red = false;
                    $grandparent->red = true;
                    $node = $grandparent;
                } else {
                    if ($node === $parent->left) {
                        $node = $parent;
                        $this->rotateRight($node);
                    }
                    $node->parent->red = false;
                    $node->parent->parent->red = true;
                    $this->rotateLeft($node->parent->parent);
                }
            }
        }
        $this->root->red = false;
    }

    private function rotateLeft(RBTreeNode $x): void {
        $y = $x->right;
        $x->right = $y->left;
        if ($y->left !== null) $y->left->parent = $x;
        $y->parent = $x->parent;
        if ($x->parent === null) {
            $this->root = $y;
        } elseif ($x === $x->parent->left) {
            $x->parent->left = $y;
        } else {
            $x->parent->right = $y;
        }
        $y->left = $x;
        $x->parent = $y;
    }

    private function rotateRight(RBTreeNode $x): void {
        $y = $x->left;
        $x->left = $y->right;
        if ($y->right !== null) $y->right->parent = $x;
        $y->parent = $x->parent;
        if ($x->parent === null) {
            $this->root = $y;
        } elseif ($x === $x->parent->right) {
            $x->parent->right = $y;
        } else {
            $x->parent->left = $y;
        }
        $y->right = $x;
        $x->parent = $y;
    }

    public function inOrder(): array {
        $result = [];
        $this->inOrderTraverse($this->root, $result);
        return $result;
    }

    private function inOrderTraverse(?RBTreeNode $node, array &$result): void {
        if ($node === null) return;
        $this->inOrderTraverse($node->left, $result);
        $result[] = $node->value;
        $this->inOrderTraverse($node->right, $result);
    }

    public function verifyProperties(): array {
        return [
            'root_is_black' => $this->root === null || !$this->root->red,
            'no_consecutive_reds' => $this->checkNoConsecutiveReds($this->root),
            'black_height' => $this->blackHeight($this->root),
            'size' => $this->size,
        ];
    }

    private function checkNoConsecutiveReds(?RBTreeNode $node): bool {
        if ($node === null) return true;
        if ($node->red) {
            if ($node->left !== null && $node->left->red) return false;
            if ($node->right !== null && $node->right->red) return false;
        }
        return $this->checkNoConsecutiveReds($node->left) && $this->checkNoConsecutiveReds($node->right);
    }

    private function blackHeight(?RBTreeNode $node): int {
        if ($node === null) return 1;
        $left = $this->blackHeight($node->left);
        $right = $this->blackHeight($node->right);
        if ($left !== $right) return -1;
        return $left + ($node->red ? 0 : 1);
    }
}

class BloomFilter {
    private array $bits = [];
    private int $size;
    private int $hashCount;
    private int $count = 0;

    public function __construct(int $size, int $hashCount = 3) {
        $this->size = $size;
        $this->hashCount = $hashCount;
        $this->bits = array_fill(0, $size, false);
    }

    public function add(string $item): void {
        for ($i = 0; $i < $this->hashCount; $i++) {
            $hash = $this->hash($item, $i);
            $this->bits[$hash] = true;
        }
        $this->count++;
    }

    public function mightContain(string $item): bool {
        for ($i = 0; $i < $this->hashCount; $i++) {
            $hash = $this->hash($item, $i);
            if (!$this->bits[$hash]) return false;
        }
        return true;
    }

    private function hash(string $item, int $seed): int {
        $h = 0;
        $len = strlen($item);
        for ($i = 0; $i < $len; $i++) {
            $h = (($h << 5) + $h + ord($item[$i]) + $seed * 31) & 0x7FFFFFFF;
        }
        return $h % $this->size;
    }

    public function getCount(): int { return $this->count; }
    public function getBitCount(): int {
        return count(array_filter($this->bits));
    }
    public function getFillRatio(): float {
        return $this->getBitCount() / $this->size;
    }
}

class ConsistentHash {
    private array $ring = [];
    private int $replicas;
    private array $nodes = [];

    public function __construct(int $replicas = 150) {
        $this->replicas = $replicas;
    }

    public function addNode(string $node): void {
        $this->nodes[$node] = true;
        for ($i = 0; $i < $this->replicas; $i++) {
            $hash = $this->hash($node . ':' . $i);
            $this->ring[$hash] = $node;
        }
        ksort($this->ring);
    }

    public function removeNode(string $node): void {
        unset($this->nodes[$node]);
        for ($i = 0; $i < $this->replicas; $i++) {
            $hash = $this->hash($node . ':' . $i);
            unset($this->ring[$hash]);
        }
    }

    public function getNode(string $key): ?string {
        if (empty($this->ring)) return null;
        $hash = $this->hash($key);
        foreach ($this->ring as $ringHash => $node) {
            if ($ringHash >= $hash) return $node;
        }
        return array_values($this->ring)[0];
    }

    private function hash(string $key): int {
        $h = 0;
        $len = strlen($key);
        for ($i = 0; $i < $len; $i++) {
            $h = (($h << 5) + $h + ord($key[$i])) & 0x7FFFFFFF;
        }
        return $h;
    }

    public function getNodes(): array {
        return array_keys($this->nodes);
    }

    public function getDistribution(array $keys): array {
        $dist = [];
        foreach ($keys as $key) {
            $node = $this->getNode($key);
            if ($node !== null) {
                if (!isset($dist[$node])) $dist[$node] = 0;
                $dist[$node]++;
            }
        }
        return $dist;
    }
}

// === 测试 ===

echo "--- Red-Black Tree ---\n";
$rbt = new RedBlackTree();
$values = [7, 3, 18, 10, 22, 8, 11, 26, 15, 1, 5, 12, 2, 9, 20];
foreach ($values as $v) $rbt->insert($v);

echo "InOrder: " . implode(",", $rbt->inOrder()) . "\n";
$props = $rbt->verifyProperties();
echo "Root is black: " . var_export($props['root_is_black'], true) . "\n";
echo "No consecutive reds: " . var_export($props['no_consecutive_reds'], true) . "\n";
echo "Black height: " . $props['black_height'] . "\n";
echo "Size: " . $props['size'] . "\n";

echo "\n--- Bloom Filter ---\n";
$bf = new BloomFilter(100, 3);
$words = ['apple', 'banana', 'cherry', 'date', 'elderberry'];
foreach ($words as $w) $bf->add($w);

foreach ($words as $w) {
    echo "Contains '$w': " . var_export($bf->mightContain($w), true) . "\n";
}
$nonWords = ['grape', 'kiwi', 'mango', 'orange', 'peach'];
$falsePositives = 0;
foreach ($nonWords as $w) {
    if ($bf->mightContain($w)) {
        $falsePositives++;
        echo "FALSE POSITIVE: '$w'\n";
    }
}
echo "False positives: $falsePositives / " . count($nonWords) . "\n";
echo "Fill ratio: " . round($bf->getFillRatio() * 100, 1) . "%\n";

echo "\n--- Consistent Hashing ---\n";
$ch = new ConsistentHash(100);
$ch->addNode('node1');
$ch->addNode('node2');
$ch->addNode('node3');

$keys = [];
for ($i = 0; $i < 100; $i++) {
    $keys[] = "key-$i";
}

$dist = $ch->getDistribution($keys);
echo "Distribution (3 nodes):\n";
ksort($dist);
foreach ($dist as $node => $count) {
    echo "  $node: $count keys (" . round($count / 100 * 100, 1) . "%)\n";
}

echo "\nAdd node4:\n";
$ch->addNode('node4');
$dist2 = $ch->getDistribution($keys);
ksort($dist2);
$migrated = 0;
foreach ($dist2 as $node => $count) {
    $old = $dist[$node] ?? 0;
    $diff = $count - $old;
    echo "  $node: $count keys (delta: $diff)\n";
    if ($diff != 0) $migrated += abs($diff);
}
echo "Keys migrated: " . ($migrated / 2) . "\n";

echo "\nRemove node2:\n";
$ch->removeNode('node2');
$dist3 = $ch->getDistribution($keys);
ksort($dist3);
foreach ($dist3 as $node => $count) {
    echo "  $node: $count keys\n";
}

echo "\n=== c033 Done ===\n";
