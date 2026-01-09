<?php
class Node {
    public $value;
    public $next;
    
    public function __construct($value) {
        $this->value = $value;
    }
    
    public function __destruct() {
        echo "Destroying node: " . $this->value . "\n";
    }
}

$node1 = new Node("1");
$node2 = new Node("2");
$node3 = new Node("3");

$node1->next = $node2;
$node2->next = $node3;
$node3->next = $node1;

echo "Created circular linked list\n";

unset($node1);
echo "After unset node1\n";

unset($node2);
echo "After unset node2\n";

unset($node3);
echo "After unset node3\n";
?>