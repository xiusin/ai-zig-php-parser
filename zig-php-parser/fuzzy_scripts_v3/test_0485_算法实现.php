<?php
class TreeNode9 {
    public $value;
    public $left = null;
    public $right = null;
    
    public function __construct($v) {
        $this->value = $v;
    }
}

function insert_9($node, $value) {
    if ($node === null) {
        return new TreeNode9($value);
    }
    
    if ($value < $node->value) {
        $node->left = insert_9($node->left, $value);
    } else {
        $node->right = insert_9($node->right, $value);
    }
    
    return $node;
}

function inorder_9($node, &$result) {
    if ($node !== null) {
        inorder_9($node->left, $result);
        $result[] = $node->value;
        inorder_9($node->right, $result);
    }
}

function tree_height_9($node) {
    if ($node === null) return 0;
    return 1 + max(tree_height_9($node->left), tree_height_9($node->right));
}

$root = null;
$values = [49, 27, 46, 17, 39];
foreach ($values as $v) {
    $root = insert_9($root, $v);
}

$inorderResult = [];
inorder_9($root, $inorderResult);

echo implode(",", $inorderResult) . "\n";
echo tree_height_9($root) . "\n";
