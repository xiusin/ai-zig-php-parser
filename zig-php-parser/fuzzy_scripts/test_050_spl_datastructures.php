<?php
// SPL数据结构测试

// SplFixedArray
$fixedArray = new SplFixedArray(5);
for ($i = 0; $i < 5; $i++) {
    $fixedArray[$i] = $i * 10;
}
echo "SplFixedArray[2]: " . $fixedArray[2] . "\n";
echo "SplFixedArray count: " . $fixedArray->count() . "\n";

// SplDoublyLinkedList
$list = new SplDoublyLinkedList();
$list->push('a');
$list->push('b');
$list->push('c');
$list->unshift('start');
echo "DLL top: " . $list->top() . "\n";
echo "DLL bottom: " . $list->bottom() . "\n";
echo "DLL pop: " . $list->pop() . "\n";
echo "DLL shift: " . $list->shift() . "\n";

// SplStack
$stack = new SplStack();
$stack->push(1);
$stack->push(2);
$stack->push(3);
echo "Stack top: " . $stack->top() . "\n";
echo "Stack pop: " . $stack->pop() . "\n";
echo "Stack count: " . $stack->count() . "\n";

// SplQueue
$queue = new SplQueue();
$queue->enqueue('first');
$queue->enqueue('second');
$queue->enqueue('third');
echo "Queue bottom: " . $queue->bottom() . "\n";
echo "Queue dequeue: " . $queue->dequeue() . "\n";
echo "Queue count: " . $queue->count() . "\n";

// SplMinHeap
$minHeap = new SplMinHeap();
$minHeap->insert(5);
$minHeap->insert(2);
$minHeap->insert(8);
$minHeap->insert(1);
echo "MinHeap top: " . $minHeap->top() . "\n";
$minHeap->extract();
echo "After extract: " . $minHeap->top() . "\n";

// SplMaxHeap
$maxHeap = new SplMaxHeap();
$maxHeap->insert(5);
$maxHeap->insert(2);
$maxHeap->insert(8);
$maxHeap->insert(1);
echo "MaxHeap top: " . $maxHeap->top() . "\n";

// SplPriorityQueue
$pq = new SplPriorityQueue();
$pq->insert('low', 1);
$pq->insert('high', 10);
$pq->insert('medium', 5);
$pq->setExtractFlags(SplPriorityQueue::EXTR_DATA);
echo "Priority top: " . $pq->top() . "\n";

// SplObjectStorage
$storage = new SplObjectStorage();
$obj1 = new stdClass();
$obj2 = new stdClass();
$obj1->name = 'obj1';
$obj2->name = 'obj2';

$storage->attach($obj1, 'data1');
$storage->attach($obj2, 'data2');
echo "Storage contains obj1: " . var_export($storage->contains($obj1), true) . "\n";
echo "Storage count: " . $storage->count() . "\n";
$storage->detach($obj1);
echo "After detach count: " . $storage->count() . "\n";

// SplFixedArray转数组
$fixed = new SplFixedArray(3);
$fixed[0] = 'a';
$fixed[1] = 'b';
$fixed[2] = 'c';
$arr = $fixed->toArray();
echo "toArray: " . implode(', ', $arr) . "\n";

// SplDoublyLinkedList遍历模式
$dll = new SplDoublyLinkedList();
$dll->push(1);
$dll->push(2);
$dll->push(3);

$dll->setIteratorMode(SplDoublyLinkedList::IT_MODE_FIFO);
echo "FIFO mode:\n";
foreach ($dll as $val) {
    echo "  $val\n";
}

$dll->setIteratorMode(SplDoublyLinkedList::IT_MODE_LIFO);
echo "LIFO mode:\n";
foreach ($dll as $val) {
    echo "  $val\n";
}

// SplFixedArray调整大小
$resizeable = SplFixedArray::fromArray([1, 2, 3, 4, 5]);
$resizeable->setSize(3);
echo "After resize: " . $resizeable->getSize() . "\n";

echo "SPL data structure tests completed\n";
