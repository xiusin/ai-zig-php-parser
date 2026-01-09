<?php
class TreeNode {
    public $value;
    public $children = [];

    public function __construct($value) {
        $this->value = $value;
    }

    public function addChild($node) {
        $this->children[] = $node;
    }

    public function traverse($depth = 0) {
        echo str_repeat("  ", $depth) . $this->value . "\n";
        foreach ($this->children as $child) {
            $child->traverse($depth + 1);
        }
    }
}

$root = new TreeNode("Root");
$child1 = new TreeNode("Child1");
$child2 = new TreeNode("Child2");
$grandchild1 = new TreeNode("GrandChild1");
$grandchild2 = new TreeNode("GrandChild2");

$child1->addChild($grandchild1);
$child1->addChild($grandchild2);
$root->addChild($child1);
$root->addChild($child2);

$root->traverse();
