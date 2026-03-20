<?php
class TreeNode {
    public function __construct(
        public mixed $value,
        public ?TreeNode $left = null,
        public ?TreeNode $right = null
    ) {}
}

function inorder(?TreeNode $node): array {
    if ($node === null) return [];
    return array_merge(inorder($node->left), [$node->value], inorder($node->right));
}

function preorder(?TreeNode $node): array {
    if ($node === null) return [];
    return array_merge([$node->value], preorder($node->left), preorder($node->right));
}

function postorder(?TreeNode $node): array {
    if ($node === null) return [];
    return array_merge(postorder($node->left), postorder($node->right), [$node->value]);
}

function levelOrder(TreeNode $root): array {
    $result = [];
    $queue = [$root];

    while (!empty($queue)) {
        $node = array_shift($queue);
        $result[] = $node->value;
        if ($node->left) $queue[] = $node->left;
        if ($node->right) $queue[] = $node->right;
    }

    return $result;
}

$root = new TreeNode(1,
    new TreeNode(2, new TreeNode(4), new TreeNode(5)),
    new TreeNode(3, new TreeNode(6), new TreeNode(7))
);

echo implode(',', inorder($root)) . "\n";
echo implode(',', preorder($root)) . "\n";
echo implode(',', postorder($root)) . "\n";
echo implode(',', levelOrder($root)) . "\n";
echo "OK\n";
