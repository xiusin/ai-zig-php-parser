<?php
// 极度混搭: B+树索引 + 范围查询 + 页管理 + 搜索
echo "=== f081: B+Tree Index + Range Query + Pages ===\n";

class BPlusTreeNode {
    public array $keys = [];
    public array $children = [];
    public ?BPlusTreeNode $next = null; // 叶子节点链表
    public bool $isLeaf;

    public function __construct(bool $isLeaf = false) {
        $this->isLeaf = $isLeaf;
    }
}

class BPlusTree {
    private BPlusTreeNode $root;
    private int $nodeCount = 0;

    public function __construct(private int $order = 4) {
        $this->root = new BPlusTreeNode(true);
        $this->nodeCount++;
    }

    public function insert(int $key, mixed $value): void {
        $leaf = $this->findLeaf($key);
        $insertPos = 0;
        while ($insertPos < count($leaf->keys) && $leaf->keys[$insertPos] < $key) $insertPos++;
        array_splice($leaf->keys, $insertPos, 0, [$key]);
        array_splice($leaf->children, $insertPos, 0, [$value]);

        if (count($leaf->keys) >= $this->order) {
            $this->splitLeaf($leaf);
        }
    }

    private function findLeaf(int $key): BPlusTreeNode {
        $node = $this->root;
        while (!$node->isLeaf) {
            $i = 0;
            while ($i < count($node->keys) && $key >= $node->keys[$i]) $i++;
            $node = $node->children[$i];
        }
        return $node;
    }

    private function splitLeaf(BPlusTreeNode $leaf): void {
        $mid = (int)(count($leaf->keys) / 2);
        $newLeaf = new BPlusTreeNode(true);
        $newLeaf->keys = array_slice($leaf->keys, $mid);
        $newLeaf->children = array_slice($leaf->children, $mid);
        $leaf->keys = array_slice($leaf->keys, 0, $mid);
        $leaf->children = array_slice($leaf->children, 0, $mid);
        $newLeaf->next = $leaf->next;
        $leaf->next = $newLeaf;
        $this->nodeCount++;

        $upKey = $newLeaf->keys[0];
        $this->insertInParent($leaf, $upKey, $newLeaf);
    }

    private function insertInParent(BPlusTreeNode $left, int $key, BPlusTreeNode $right): void {
        if ($left === $this->root) {
            $newRoot = new BPlusTreeNode(false);
            $newRoot->keys = [$key];
            $newRoot->children = [$left, $right];
            $this->root = $newRoot;
            $this->nodeCount++;
            return;
        }
        // 简化: 不处理内部节点分裂
        $newNode = new BPlusNodeProxy($this->root, $left, $key, $right);
    }

    public function search(int $key): mixed {
        $leaf = $this->findLeaf($key);
        $pos = array_search($key, $leaf->keys);
        if ($pos === false) return null;
        return $leaf->children[$pos];
    }

    public function rangeQuery(int $low, int $high): array {
        $result = [];
        $leaf = $this->findLeaf($low);
        while ($leaf !== null) {
            for ($i = 0; $i < count($leaf->keys); $i++) {
                if ($leaf->keys[$i] > $high) return $result;
                if ($leaf->keys[$i] >= $low) {
                    $result[] = ['key' => $leaf->keys[$i], 'value' => $leaf->children[$i]];
                }
            }
            $leaf = $leaf->next;
        }
        return $result;
    }

    public function getAll(): array {
        $result = [];
        $leaf = $this->findLeaf(-1);
        while ($leaf !== null) {
            for ($i = 0; $i < count($leaf->keys); $i++) {
                $result[] = ['key' => $leaf->keys[$i], 'value' => $leaf->children[$i]];
            }
            $leaf = $leaf->next;
        }
        return $result;
    }

    public function getNodeCount(): int { return $this->nodeCount; }
}

class BPlusNodeProxy {
    public function __construct(BPlusTreeNode $root, BPlusTreeNode $left, int $key, BPlusTreeNode $right) {
        // 简化代理
        $root->keys[] = $key;
        $root->children[] = $right;
    }
}

// 测试
echo "--- B+Tree Insert & Search ---\n";
$tree = new BPlusTree(4);
$data = [10, 20, 5, 6, 12, 30, 7, 17, 25, 31, 3, 1, 40, 50, 15, 8];
foreach ($data as $k => $v) {
    $tree->insert($v, "value_$v");
}
echo "Inserted: " . implode(', ', $data) . "\n";
echo "Node count: " . $tree->getNodeCount() . "\n";

echo "\n--- Point Search ---\n";
$searchKeys = [10, 20, 25, 99, 1, 50];
foreach ($searchKeys as $k) {
    $result = $tree->search($k);
    echo "  search($k) = " . var_export($result, true) . "\n";
}

echo "\n--- Range Query ---\n";
$ranges = [[5, 15], [1, 50], [20, 40], [0, 100], [30, 30]];
foreach ($ranges as [$low, $high]) {
    $results = $tree->rangeQuery($low, $high);
    $keys = array_map(fn($r) => $r['key'], $results);
    echo "  range($low, $high) = [" . implode(', ', $keys) . "] (" . count($results) . " items)\n";
}

echo "\n--- Full Scan (via leaf chain) ---\n";
$all = $tree->getAll();
$allKeys = array_map(fn($r) => $r['key'], $all);
echo "All keys (sorted via leaf chain): " . implode(', ', $allKeys) . "\n";
$sorted = $data; sort($sorted);
echo "Matches sorted input: " . var_export($allKeys === $sorted, true) . "\n";

echo "=== f081 Done ===\n";
