<?php
// 测试59: SPL数据结构
// SplStack
$stack = new SplStack();
$stack->push("first");
$stack->push("second");
$stack->push("third");

echo "Stack (LIFO):\n";
foreach ($stack as $item) {
    echo "  $item\n";
}

// SplQueue
$queue = new SplQueue();
$queue->enqueue("one");
$queue->enqueue("two");
$queue->enqueue("three");

echo "Queue (FIFO):\n";
foreach ($queue as $item) {
    echo "  $item\n";
}

// SplFixedArray
$fixed = new SplFixedArray(5);
$fixed[0] = "a";
$fixed[2] = "b";
$fixed[4] = "c";
echo "Fixed array size: " . count($fixed) . "\n";
echo "Fixed array: " . implode(", ", array_filter((array)$fixed)) . "\n";

// SplObjectStorage
$storage = new SplObjectStorage();
$obj1 = new stdClass();
$obj2 = new stdClass();
$obj3 = new stdClass();

$storage[$obj1] = "data1";
$storage[$obj2] = "data2";
$storage->attach($obj3, "data3");

echo "Storage count: " . count($storage) . "\n";
echo "Contains obj1: " . ($storage->contains($obj1) ? "yes" : "no") . "\n";

// SplDoublyLinkedList
$list = new SplDoublyLinkedList();
$list->push("a");
$list->push("b");
$list->unshift("c");

echo "List (forward):\n";
$list->setIteratorMode(SplDoublyLinkedList::IT_MODE_FIFO);
foreach ($list as $item) {
    echo "  $item\n";
}

echo "List (reverse):\n";
$list->setIteratorMode(SplDoublyLinkedList::IT_MODE_LIFO);
foreach ($list as $item) {
    echo "  $item\n";
}

// SplHeap (使用自定义比较)
class IntHeap extends SplHeap {
    protected function compare($a, $b): int {
        return $b <=> $a;
    }
}

$heap = new IntHeap();
$heap->insert(5);
$heap->insert(1);
$heap->insert(10);
$heap->insert(3);

echo "Heap (max first):\n";
while (!$heap->isEmpty()) {
    echo "  " . $heap->extract() . "\n";
}

// SplPriorityQueue
$pq = new SplPriorityQueue();
$pq->insert("low", 1);
$pq->insert("high", 10);
$pq->insert("medium", 5);

echo "Priority queue:\n";
while (!$pq->isEmpty()) {
    echo "  " . $pq->extract() . "\n";
}
?>