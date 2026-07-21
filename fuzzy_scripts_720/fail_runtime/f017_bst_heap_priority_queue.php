<?php
// 极度混搭: 二叉树/AVL/堆 + 遍历 + 旋转 + 优先级队列
echo "=== f017: BST + AVL + Heap + Traversal ===\n";

class BSTNode {
    public ?BSTNode $left = null;
    public ?BSTNode $right = null;
    public int $height = 1;

    public function __construct(public int $key, public mixed $value = null) {}
}

class BST {
    protected ?BSTNode $root = null;

    public function insert(int $key, mixed $value = null): void {
        $this->root = $this->insertNode($this->root, $key, $value);
    }

    protected function insertNode(?BSTNode $node, int $key, mixed $value): BSTNode {
        if ($node === null) return new BSTNode($key, $value);
        if ($key < $node->key) $node->left = $this->insertNode($node->left, $key, $value);
        elseif ($key > $node->key) $node->right = $this->insertNode($node->right, $key, $value);
        else $node->value = $value;
        return $node;
    }

    public function search(int $key): mixed {
        $node = $this->root;
        while ($node !== null) {
            if ($key === $node->key) return $node->value;
            $node = $key < $node->key ? $node->left : $node->right;
        }
        return null;
    }

    public function contains(int $key): bool {
        return $this->search($key) !== null;
    }

    public function min(): ?int {
        $node = $this->root;
        while ($node !== null && $node->left !== null) $node = $node->left;
        return $node?->key;
    }

    public function max(): ?int {
        $node = $this->root;
        while ($node !== null && $node->right !== null) $node = $node->right;
        return $node?->key;
    }

    public function inorder(): array {
        $result = [];
        $this->inorderHelper($this->root, $result);
        return $result;
    }

    private function inorderHelper(?BSTNode $node, array &$result): void {
        if ($node === null) return;
        $this->inorderHelper($node->left, $result);
        $result[] = $node->key;
        $this->inorderHelper($node->right, $result);
    }

    public function preorder(): array {
        $result = [];
        $this->preorderHelper($this->root, $result);
        return $result;
    }

    private function preorderHelper(?BSTNode $node, array &$result): void {
        if ($node === null) return;
        $result[] = $node->key;
        $this->preorderHelper($node->left, $result);
        $this->preorderHelper($node->right, $result);
    }

    public function postorder(): array {
        $result = [];
        $this->postorderHelper($this->root, $result);
        return $result;
    }

    private function postorderHelper(?BSTNode $node, array &$result): void {
        if ($node === null) return;
        $this->postorderHelper($node->left, $result);
        $this->postorderHelper($node->right, $result);
        $result[] = $node->key;
    }

    public function levelOrder(): array {
        if ($this->root === null) return [];
        $result = [];
        $queue = [$this->root];
        while (!empty($queue)) {
            $node = array_shift($queue);
            $result[] = $node->key;
            if ($node->left !== null) $queue[] = $node->left;
            if ($node->right !== null) $queue[] = $node->right;
        }
        return $result;
    }

    public function height(): int {
        return $this->heightHelper($this->root);
    }

    private function heightHelper(?BSTNode $node): int {
        if ($node === null) return 0;
        return 1 + max($this->heightHelper($node->left), $this->heightHelper($node->right));
    }

    public function count(): int {
        return $this->countHelper($this->root);
    }

    private function countHelper(?BSTNode $node): int {
        if ($node === null) return 0;
        return 1 + $this->countHelper($node->left) + $this->countHelper($node->right);
    }
}

class MinHeap {
    private array $heap = [];

    public function insert(int $val): void {
        $this->heap[] = $val;
        $this->siftUp(count($this->heap) - 1);
    }

    public function extractMin(): ?int {
        if (empty($this->heap)) return null;
        $min = $this->heap[0];
        $last = array_pop($this->heap);
        if (!empty($this->heap)) {
            $this->heap[0] = $last;
            $this->siftDown(0);
        }
        return $min;
    }

    public function peek(): ?int {
        return $this->heap[0] ?? null;
    }

    private function siftUp(int $idx): void {
        while ($idx > 0) {
            $parent = (int)(($idx - 1) / 2);
            if ($this->heap[$parent] <= $this->heap[$idx]) break;
            $tmp = $this->heap[$parent];
            $this->heap[$parent] = $this->heap[$idx];
            $this->heap[$idx] = $tmp;
            $idx = $parent;
        }
    }

    private function siftDown(int $idx): void {
        $n = count($this->heap);
        while (true) {
            $left = 2 * $idx + 1;
            $right = 2 * $idx + 2;
            $smallest = $idx;
            if ($left < $n && $this->heap[$left] < $this->heap[$smallest]) $smallest = $left;
            if ($right < $n && $this->heap[$right] < $this->heap[$smallest]) $smallest = $right;
            if ($smallest === $idx) break;
            $tmp = $this->heap[$smallest];
            $this->heap[$smallest] = $this->heap[$idx];
            $this->heap[$idx] = $tmp;
            $idx = $smallest;
        }
    }

    public function size(): int { return count($this->heap); }
    public function toArray(): array { return $this->heap; }
}

// === 测试 ===
echo "--- BST ---\n";
$bst = new BST();
$keys = [50, 30, 70, 20, 40, 60, 80, 10, 25, 35, 45];
foreach ($keys as $k) $bst->insert($k, "value_$k");

echo "Inorder: " . implode(', ', $bst->inorder()) . "\n";
echo "Preorder: " . implode(', ', $bst->preorder()) . "\n";
echo "Postorder: " . implode(', ', $bst->postorder()) . "\n";
echo "LevelOrder: " . implode(', ', $bst->levelOrder()) . "\n";
echo "Min: " . $bst->min() . "\n";
echo "Max: " . $bst->max() . "\n";
echo "Height: " . $bst->height() . "\n";
echo "Count: " . $bst->count() . "\n";
echo "Search 40: " . var_export($bst->contains(40), true) . "\n";
echo "Search 99: " . var_export($bst->contains(99), true) . "\n";
echo "Get 40: " . $bst->search(40) . "\n";

echo "\n--- Min Heap ---\n";
$heap = new MinHeap();
$values = [9, 5, 2, 7, 1, 8, 3, 6, 4];
foreach ($values as $v) $heap->insert($v);
echo "Heap array: " . implode(', ', $heap->toArray()) . "\n";
echo "Peek: " . $heap->peek() . "\n";

$sorted = [];
while (($v = $heap->extractMin()) !== null) {
    $sorted[] = $v;
}
echo "Extracted (sorted): " . implode(', ', $sorted) . "\n";
echo "Heap empty: " . var_export($heap->size() === 0, true) . "\n";

// 堆排序验证
$isSorted = true;
for ($i = 1; $i < count($sorted); $i++) {
    if ($sorted[$i] < $sorted[$i - 1]) { $isSorted = false; break; }
}
echo "Is sorted: " . var_export($isSorted, true) . "\n";

echo "\n--- Priority Queue ---\n";
class TaskItem {
    public function __construct(public int $priority, public string $name) {}
}

$pq = new MinHeap();
$tasks = [
    new TaskItem(3, 'Low'),
    new TaskItem(1, 'Critical'),
    new TaskItem(2, 'Medium'),
    new TaskItem(1, 'Urgent'),
    new TaskItem(4, 'Background'),
];

// 使用优先级值插入堆
foreach ($tasks as $t) {
    $pq->insert($t->priority);
}

$queue = [];
while (($p = $pq->extractMin()) !== null) {
    $queue[] = $p;
}
echo "Priority order: " . implode(', ', $queue) . "\n";

echo "=== f017 Done ===\n";
