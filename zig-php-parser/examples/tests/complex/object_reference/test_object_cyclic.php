<?php
class Node {
    public $name;
    public $parent;
    public $children = [];

    public function __construct($name) {
        $this->name = $name;
    }

    public function addChild($child) {
        $this->children[] = $child;
        $child->parent = $this;
    }
}

$root = new Node("Root");
$child1 = new Node("Child1");
$child2 = new Node("Child2");

$root->addChild($child1);
$root->addChild($child2);

echo "Root children count: " . count($root->children) . "\n";
echo "Child1 parent: " . $child1->parent->name . "\n";
echo "Child2 parent: " . $child2->parent->name . "\n";
