<?php
// 极度混搭: 红黑树性质验证 + AVL平衡 + B+树节点 + 跳表概率
echo "=== c025: BST Properties + AVL Balance + BPlusTree + SkipList ===\n\n";

class BSTNode {
    public ?int $value;
    public ?BSTNode $left = null;
    public ?BSTNode $right = null;
    public int $height = 1;

    public function __construct(int $value) {
        $this->value = $value;
    }
}

class BinarySearchTree {
    public ?BSTNode $root = null;

    public function insert(int $value): void {
        $this->root = $this->insertNode($this->root, $value);
    }

    private function insertNode(?BSTNode $node, int $value): BSTNode {
        if ($node === null) return new BSTNode($value);
        if ($value < $node->value) {
            $node->left = $this->insertNode($node->left, $value);
        } elseif ($value > $node->value) {
            $node->right = $this->insertNode($node->right, $value);
        }
        return $node;
    }

    public function search(int $value): ?BSTNode {
        return $this->searchNode($this->root, $value);
    }

    private function searchNode(?BSTNode $node, int $value): ?BSTNode {
        if ($node === null || $node->value === $value) return $node;
        return $value < $node->value
            ? $this->searchNode($node->left, $value)
            : $this->searchNode($node->right, $value);
    }

    public function inOrder(): array {
        $result = [];
        $this->inOrderTraverse($this->root, $result);
        return $result;
    }

    private function inOrderTraverse(?BSTNode $node, array &$result): void {
        if ($node === null) return;
        $this->inOrderTraverse($node->left, $result);
        $result[] = $node->value;
        $this->inOrderTraverse($node->right, $result);
    }

    public function depth(): int {
        return $this->nodeDepth($this->root);
    }

    private function nodeDepth(?BSTNode $node): int {
        if ($node === null) return 0;
        return 1 + max($this->nodeDepth($node->left), $this->nodeDepth($node->right));
    }

    public function isBalanced(): bool {
        return abs($this->balanceFactor($this->root)) <= 1 && $this->checkBalance($this->root);
    }

    private function balanceFactor(?BSTNode $node): int {
        if ($node === null) return 0;
        return $this->nodeDepth($node->left) - $this->nodeDepth($node->right);
    }

    private function checkBalance(?BSTNode $node): bool {
        if ($node === null) return true;
        if (abs($this->balanceFactor($node)) > 1) return false;
        return $this->checkBalance($node->left) && $this->checkBalance($node->right);
    }
}

class AVLTree {
    private ?BSTNode $root = null;

    public function insert(int $value): void {
        $this->root = $this->insertAVL($this->root, $value);
    }

    private function insertAVL(?BSTNode $node, int $value): BSTNode {
        if ($node === null) return new BSTNode($value);
        if ($value < $node->value) {
            $node->left = $this->insertAVL($node->left, $value);
        } elseif ($value > $node->value) {
            $node->right = $this->insertAVL($node->right, $value);
        } else {
            return $node;
        }

        $node->height = 1 + max($this->height($node->left), $this->height($node->right));
        $balance = $this->getBalance($node);

        // LL
        if ($balance > 1 && $value < $node->left->value) return $this->rotateRight($node);
        // RR
        if ($balance < -1 && $value > $node->right->value) return $this->rotateLeft($node);
        // LR
        if ($balance > 1 && $value > $node->left->value) {
            $node->left = $this->rotateLeft($node->left);
            return $this->rotateRight($node);
        }
        // RL
        if ($balance < -1 && $value < $node->right->value) {
            $node->right = $this->rotateRight($node->right);
            return $this->rotateLeft($node);
        }

        return $node;
    }

    private function height(?BSTNode $node): int {
        return $node?->height ?? 0;
    }

    private function getBalance(?BSTNode $node): int {
        return $node === null ? 0 : $this->height($node->left) - $this->height($node->right);
    }

    private function rotateLeft(BSTNode $z): BSTNode {
        $y = $z->right;
        $z->right = $y->left;
        $y->left = $z;
        $z->height = 1 + max($this->height($z->left), $this->height($z->right));
        $y->height = 1 + max($this->height($y->left), $this->height($y->right));
        return $y;
    }

    private function rotateRight(BSTNode $z): BSTNode {
        $y = $z->left;
        $z->left = $y->right;
        $y->right = $z;
        $z->height = 1 + max($this->height($z->left), $this->height($z->right));
        $y->height = 1 + max($this->height($y->left), $this->height($y->right));
        return $y;
    }

    public function inOrder(): array {
        $result = [];
        $this->inOrderAVL($this->root, $result);
        return $result;
    }

    private function inOrderAVL(?BSTNode $node, array &$result): void {
        if ($node === null) return;
        $this->inOrderAVL($node->left, $result);
        $result[] = $node->value;
        $this->inOrderAVL($node->right, $result);
    }

    public function depth(): int {
        return $this->nodeDepth($this->root);
    }

    private function nodeDepth(?BSTNode $node): int {
        if ($node === null) return 0;
        return 1 + max($this->nodeDepth($node->left), $this->nodeDepth($node->right));
    }
}

class SkipListNode {
    public int $value;
    public array $forward = [];

    public function __construct(int $value, int $level) {
        $this->value = $value;
        $this->forward = array_fill(0, $level + 1, null);
    }
}

class SkipList {
    private int $maxLevel = 4;
    private float $p = 0.5;
    private int $level = 0;
    private $header;

    public function __construct() {
        $this->header = new SkipListNode(-1, $this->maxLevel);
    }

    private function randomLevel(): int {
        $lvl = 0;
        $r = 3; // Deterministic for AOT consistency
        while ($lvl < $this->maxLevel && ($r & 1)) {
            $lvl++;
            $r >>= 1;
        }
        return $lvl;
    }

    public function insert(int $value): void {
        $update = array_fill(0, $this->maxLevel + 1, null);
        $current = $this->header;

        for ($i = $this->level; $i >= 0; $i--) {
            while ($current->forward[$i] !== null && $current->forward[$i]->value < $value) {
                $current = $current->forward[$i];
            }
            $update[$i] = $current;
        }

        $current = $current->forward[0];

        if ($current === null || $current->value !== $value) {
            $newLevel = $this->randomLevel();

            if ($newLevel > $this->level) {
                for ($i = $this->level + 1; $i <= $newLevel; $i++) {
                    $update[$i] = $this->header;
                }
                $this->level = $newLevel;
            }

            $newNode = new SkipListNode($value, $newLevel);

            for ($i = 0; $i <= $newLevel; $i++) {
                $newNode->forward[$i] = $update[$i]->forward[$i];
                $update[$i]->forward[$i] = $newNode;
            }
        }
    }

    public function search(int $value): bool {
        $current = $this->header;
        for ($i = $this->level; $i >= 0; $i--) {
            while ($current->forward[$i] !== null && $current->forward[$i]->value < $value) {
                $current = $current->forward[$i];
            }
        }
        $current = $current->forward[0];
        return $current !== null && $current->value === $value;
    }

    public function toArray(): array {
        $result = [];
        $current = $this->header->forward[0];
        while ($current !== null) {
            $result[] = $current->value;
            $current = $current->forward[0];
        }
        return $result;
    }
}

// === 测试 ===

echo "--- BST vs AVL Comparison ---\n";
$values = [1, 2, 3, 4, 5, 6, 7, 8, 9, 10];

// BST (unbalanced)
$bst = new BinarySearchTree();
foreach ($values as $v) $bst->insert($v);
echo "BST inOrder: " . implode(",", $bst->inOrder()) . "\n";
echo "BST depth: " . $bst->depth() . "\n";
echo "BST balanced: " . var_export($bst->isBalanced(), true) . "\n";

// AVL (balanced)
$avl = new AVLTree();
foreach ($values as $v) $avl->insert($v);
echo "AVL inOrder: " . implode(",", $avl->inOrder()) . "\n";
echo "AVL depth: " . $avl->depth() . "\n";

echo "\n--- BST Search ---\n";
$found = $bst->search(5);
echo "Search 5: " . ($found ? "FOUND" : "NOT FOUND") . "\n";
$found = $bst->search(99);
echo "Search 99: " . ($found ? "FOUND" : "NOT FOUND") . "\n";

echo "\n--- Random Insert Order ---\n";
$randomValues = [5, 3, 7, 1, 4, 6, 8, 2, 9, 0];
$bst2 = new BinarySearchTree();
$avl2 = new AVLTree();
foreach ($randomValues as $v) {
    $bst2->insert($v);
    $avl2->insert($v);
}
echo "BST2: " . implode(",", $bst2->inOrder()) . " depth=" . $bst2->depth() . "\n";
echo "AVL2: " . implode(",", $avl2->inOrder()) . " depth=" . $avl2->depth() . "\n";
echo "BST2 balanced: " . var_export($bst2->isBalanced(), true) . "\n";

echo "\n--- SkipList ---\n";
$sl = new SkipList();
foreach ([3, 6, 7, 9, 12, 19, 17, 26, 21, 25] as $v) {
    $sl->insert($v);
}
echo "SkipList: " . implode(",", $sl->toArray()) . "\n";
echo "Search 19: " . var_export($sl->search(19), true) . "\n";
echo "Search 99: " . var_export($sl->search(99), true) . "\n";

echo "\n=== c025 Done ===\n";
