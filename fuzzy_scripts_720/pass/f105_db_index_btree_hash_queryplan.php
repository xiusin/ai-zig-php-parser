<?php
// 极度混搭: 数据库索引 + B树 + 哈希索引 + 查询计划
echo "=== f105: DB Index + BTree + HashIndex + QueryPlan ===\n";

class BTreeNode {
    public array $keys = [];
    public array $values = [];
    public array $children = [];
    public bool $isLeaf = true;

    public function __construct(public int $t = 2) {} // 最小度
}

class BTree {
    private BTreeNode $root;

    public function __construct(private int $t = 2) {
        $this->root = new BTreeNode($t);
    }

    public function insert(int $key, mixed $value): void {
        $root = $this->root;
        if (count($root->keys) === 2 * $this->t - 1) {
            $newRoot = new BTreeNode($this->t);
            $newRoot->isLeaf = false;
            $newRoot->children[] = $root;
            $this->splitChild($newRoot, 0);
            $this->root = $newRoot;
        }
        $this->insertNonFull($this->root, $key, $value);
    }

    private function insertNonFull(BTreeNode $node, int $key, mixed $value): void {
        $i = count($node->keys) - 1;
        if ($node->isLeaf) {
            while ($i >= 0 && $key < $node->keys[$i]) $i--;
            $i++;
            array_splice($node->keys, $i, 0, [$key]);
            array_splice($node->values, $i, 0, [$value]);
        } else {
            while ($i >= 0 && $key < $node->keys[$i]) $i--;
            $i++;
            if (count($node->children[$i]->keys) === 2 * $this->t - 1) {
                $this->splitChild($node, $i);
                if ($key > $node->keys[$i]) $i++;
            }
            $this->insertNonFull($node->children[$i], $key, $value);
        }
    }

    private function splitChild(BTreeNode $parent, int $index): void {
        $full = $parent->children[$index];
        $newNode = new BTreeNode($this->t);
        $newNode->isLeaf = $full->isLeaf;
        $t = $this->t;
        $midKey = $full->keys[$t - 1];
        $midVal = $full->values[$t - 1];
        $newNode->keys = array_slice($full->keys, $t);
        $newNode->values = array_slice($full->values, $t);
        $full->keys = array_slice($full->keys, 0, $t - 1);
        $full->values = array_slice($full->values, 0, $t - 1);
        if (!$full->isLeaf) {
            $newNode->children = array_slice($full->children, $t);
            $full->children = array_slice($full->children, 0, $t);
        }
        array_splice($parent->keys, $index, 0, [$midKey]);
        array_splice($parent->values, $index, 0, [$midVal]);
        array_splice($parent->children, $index + 1, 0, [$newNode]);
    }

    public function search(int $key): mixed {
        return $this->searchNode($this->root, $key);
    }

    private function searchNode(BTreeNode $node, int $key): mixed {
        $i = 0;
        while ($i < count($node->keys) && $key > $node->keys[$i]) $i++;
        if ($i < count($node->keys) && $node->keys[$i] === $key) return $node->values[$i];
        if ($node->isLeaf) return null;
        return $this->searchNode($node->children[$i], $key);
    }

    public function rangeQuery(int $low, int $high): array {
        $result = [];
        $this->rangeSearch($this->root, $low, $high, $result);
        return $result;
    }

    private function rangeSearch(BTreeNode $node, int $low, int $high, array &$result): void {
        for ($i = 0; $i < count($node->keys); $i++) {
            if (!$node->isLeaf) $this->rangeSearch($node->children[$i], $low, $high, $result);
            if ($node->keys[$i] >= $low && $node->keys[$i] <= $high) {
                $result[] = ['key' => $node->keys[$i], 'value' => $node->values[$i]];
            }
        }
        if (!$node->isLeaf) $this->rangeSearch($node->children[count($node->keys)], $low, $high, $result);
    }

    public function inorder(): array {
        $result = [];
        $this->inorderTraverse($this->root, $result);
        return $result;
    }

    private function inorderTraverse(BTreeNode $node, array &$result): void {
        for ($i = 0; $i < count($node->keys); $i++) {
            if (!$node->isLeaf) $this->inorderTraverse($node->children[$i], $result);
            $result[] = $node->keys[$i];
        }
        if (!$node->isLeaf) $this->inorderTraverse($node->children[count($node->keys)], $result);
    }
}

class HashIndex {
    private array $buckets = [];
    private int $collisions = 0;

    public function __construct(private int $bucketCount = 16) {
        $this->buckets = array_fill(0, $bucketCount, []);
    }

    public function insert(string $key, mixed $value): void {
        $hash = $this->hash($key);
        if (!empty($this->buckets[$hash])) $this->collisions++;
        $this->buckets[$hash][] = ['key' => $key, 'value' => $value];
    }

    public function search(string $key): mixed {
        $hash = $this->hash($key);
        foreach ($this->buckets[$hash] as $entry) {
            if ($entry['key'] === $key) return $entry['value'];
        }
        return null;
    }

    public function delete(string $key): bool {
        $hash = $this->hash($key);
        foreach ($this->buckets[$hash] as $i => $entry) {
            if ($entry['key'] === $key) { array_splice($this->buckets[$hash], $i, 1); return true; }
        }
        return false;
    }

    private function hash(string $key): int {
        $h = 0;
        for ($i = 0; $i < strlen($key); $i++) $h = ($h * 31 + ord($key[$i])) % $this->bucketCount;
        return abs($h) % $this->bucketCount;
    }

    public function getStats(): array {
        $sizes = array_map('count', $this->buckets);
        return ['buckets' => $this->bucketCount, 'collisions' => $this->collisions, 'max_chain' => max($sizes), 'avg_chain' => array_sum($sizes) / $this->bucketCount];
    }
}

class QueryPlanner {
    public static function plan(string $query): array {
        // 简化SQL解析
        $query = trim($query);
        $type = strtoupper(explode(' ', $query)[0]);

        $plan = ['query' => $query, 'type' => $type, 'steps' => [], 'estimated_cost' => 0];

        if (str_contains(strtoupper($query), 'WHERE')) {
            $plan['steps'][] = ['op' => 'Filter', 'desc' => 'Apply WHERE condition'];
            $plan['estimated_cost'] += 10;
        }
        if (str_contains(strtoupper($query), 'JOIN')) {
            $plan['steps'][] = ['op' => 'HashJoin', 'desc' => 'Hash join tables'];
            $plan['estimated_cost'] += 50;
        }
        if (str_contains(strtoupper($query), 'GROUP BY')) {
            $plan['steps'][] = ['op' => 'Aggregate', 'desc' => 'Group and aggregate'];
            $plan['estimated_cost'] += 30;
        }
        if (str_contains(strtoupper($query), 'ORDER BY')) {
            $plan['steps'][] = ['op' => 'Sort', 'desc' => 'Sort results'];
            $plan['estimated_cost'] += 20;
        }
        if (str_contains(strtoupper($query), 'LIMIT')) {
            $plan['steps'][] = ['op' => 'Limit', 'desc' => 'Limit rows'];
            $plan['estimated_cost'] += 1;
        }
        $plan['steps'][] = ['op' => 'SeqScan', 'desc' => 'Sequential scan (or index scan)'];
        $plan['estimated_cost'] += 5;

        return $plan;
    }

    public static function explain(array $plan): string {
        $output = "QUERY PLAN\n";
        $output .= "Type: {$plan['type']}\n";
        $output .= "Estimated cost: {$plan['estimated_cost']}\n";
        $output .= "Steps:\n";
        foreach (array_reverse($plan['steps']) as $i => $step) {
            $output .= "  " . ($i + 1) . ". {$step['op']}: {$step['desc']}\n";
        }
        return $output;
    }
}

// 测试
echo "--- B-Tree Index ---\n";
$btree = new BTree(2);
$data = [10, 20, 5, 6, 12, 30, 7, 17, 25, 31, 3, 1, 40, 50, 15, 8, 45, 35, 28, 22];
foreach ($data as $k) $btree->insert($k, "val_$k");
echo "Inserted: " . implode(', ', $data) . "\n";
echo "Inorder: " . implode(', ', $btree->inorder()) . "\n";

echo "\nPoint search:\n";
foreach ([10, 30, 99, 1] as $k) echo "  search($k) = " . var_export($btree->search($k), true) . "\n";

echo "\nRange queries:\n";
foreach ([[5, 15], [20, 40], [1, 50]] as [$lo, $hi]) {
    $r = $btree->rangeQuery($lo, $hi);
    echo "  range($lo, $hi) = [" . implode(', ', array_map(fn($e) => $e['key'], $r)) . "]\n";
}

echo "\n--- Hash Index ---\n";
$hash = new HashIndex(8);
$users = ['alice' => ['age' => 30, 'city' => 'NYC'], 'bob' => ['age' => 25, 'city' => 'LA'], 'charlie' => ['age' => 35, 'city' => 'SF'], 'dave' => ['age' => 28, 'city' => 'Boston']];
foreach ($users as $name => $data) $hash->insert($name, $data);
echo "Search alice: " . json_encode($hash->search('alice')) . "\n";
echo "Search bob: " . json_encode($hash->search('bob')) . "\n";
echo "Search nonexistent: " . var_export($hash->search('zzz'), true) . "\n";
echo "Delete alice: " . var_export($hash->delete('alice'), true) . "\n";
echo "Search alice after delete: " . var_export($hash->search('alice'), true) . "\n";
echo "Stats: " . json_encode($hash->getStats()) . "\n";

echo "\n--- Query Planner ---\n";
$queries = [
    'SELECT * FROM users',
    'SELECT * FROM users WHERE age > 25',
    'SELECT * FROM users u JOIN orders o ON u.id = o.user_id',
    'SELECT city, COUNT(*) FROM users GROUP BY city',
    'SELECT * FROM users ORDER BY name LIMIT 10',
    'SELECT * FROM users u JOIN orders o ON u.id = o.user_id WHERE u.age > 25 GROUP BY u.city ORDER BY COUNT(*) DESC LIMIT 5',
];
foreach ($queries as $q) {
    $plan = QueryPlanner::plan($q);
    echo "\n" . QueryPlanner::explain($plan);
}

echo "=== f105 Done ===\n";
