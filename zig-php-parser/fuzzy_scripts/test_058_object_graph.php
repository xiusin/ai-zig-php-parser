<?php
// 测试58: 复杂的对象图与循环引用
class Node {
    public $value;
    public $children = [];
    public $parent = null;
    
    public function __construct($value) {
        $this->value = $value;
    }
    
    public function addChild(Node $child): void {
        $child->parent = $this;
        $this->children[] = $child;
    }
}

class Graph {
    public $nodes = [];
    public $edges = [];
    
    public function addNode($id): Node {
        $node = new Node($id);
        $this->nodes[$id] = $node;
        return $node;
    }
    
    public function connect($from, $to): void {
        $this->edges[$from][] = $to;
        $this->edges[$to][] = $from;
    }
}

// 构建树结构
$root = new Node("root");
$child1 = new Node("child1");
$child2 = new Node("child2");
$grandchild = new Node("grandchild");

$root->addChild($child1);
$root->addChild($child2);
$child1->addChild($grandchild);

// 创建循环引用
$grandchild->children[] = $root; // 循环!

// 遍历树
function traverse(Node $node, int $depth = 0, array &$visited = []): void {
    if (in_array($node->value, $visited, true)) {
        echo str_repeat("  ", $depth) . "{$node->value} (cycle detected)\n";
        return;
    }
    $visited[] = $node->value;
    echo str_repeat("  ", $depth) . "{$node->value}\n";
    foreach ($node->children as $child) {
        traverse($child, $depth + 1, $visited);
    }
}

traverse($root);

// 清理循环引用
$grandchild->children = [];
$root = $child1 = $child2 = $grandchild = null;
gc_collect_cycles();

// 双向链表
class ListNode {
    public $value;
    public $prev = null;
    public $next = null;
    
    public function __construct($value) {
        $this->value = $value;
    }
}

$head = new ListNode(1);
$middle = new ListNode(2);
$tail = new ListNode(3);

$head->next = $middle;
$middle->prev = $head;
$middle->next = $tail;
$tail->prev = $middle;

// 遍历双向链表
$current = $head;
while ($current) {
    echo $current->value . " ";
    $current = $current->next;
}
echo "\n";

// 反向遍历
$current = $tail;
while ($current) {
    echo $current->value . " ";
    $current = $current->prev;
}
echo "\n";

$head = $middle = $tail = null;
gc_collect_cycles();
?>
