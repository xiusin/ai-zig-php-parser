<?php
// Test 014: SPL classes, iterators, and data structures
class SplLab {
    public function process(): string {
        $out = "";

        // SplFixedArray
        $fixed = new SplFixedArray(3);
        $fixed[0] = 'first';
        $fixed[1] = 'second';
        $fixed[2] = 'third';
        $out .= "SplFixedArray count: " . $fixed->count() . "\n";
        $out .= "SplFixedArray[1]: " . $fixed[1] . "\n";

        // Convert to array
        $arr = $fixed->toArray();
        $out .= "toArray: " . implode(',', $arr) . "\n";

        // SplStack
        $stack = new SplStack();
        $stack->push('a');
        $stack->push('b');
        $stack->push('c');
        $out .= "\nSplStack top: " . $stack->top() . "\n";
        $out .= "SplStack pop: " . $stack->pop() . "\n";
        $out .= "SplStack count: " . count($stack) . "\n";

        // SplQueue
        $queue = new SplQueue();
        $queue->enqueue('first');
        $queue->enqueue('second');
        $queue->enqueue('third');
        $out .= "\nSplQueue count: " . count($queue) . "\n";
        $out .= "SplQueue dequeue: " . $queue->dequeue() . "\n";

        // SplMinHeap
        $heap = new SplMinHeap();
        $heap->insert(30);
        $heap->insert(10);
        $heap->insert(50);
        $heap->insert(20);
        $out .= "\nSplMinHeap extract: " . $heap->extract() . "\n";
        $out .= "SplMinHeap top: " . $heap->top() . "\n";

        // SplMaxHeap
        $maxHeap = new SplMaxHeap();
        $maxHeap->insert(30);
        $maxHeap->insert(10);
        $maxHeap->insert(50);
        $out .= "\nSplMaxHeap extract: " . $maxHeap->extract() . "\n";

        // SplPriorityQueue
        $pq = new SplPriorityQueue();
        $pq->insert('low', 1);
        $pq->insert('high', 10);
        $pq->insert('medium', 5);
        $out .= "\nSplPriorityQueue order:\n";
        while (!$pq->isEmpty()) {
            $out .= "  " . $pq->extract() . "\n";
        }

        // SplDoublyLinkedList
        $list = new SplDoublyLinkedList();
        $list->push('a');
        $list->push('b');
        $list->push('c');
        $list->unshift('start');
        $out .= "\nSplDoublyLinkedList:\n";
        for ($list->rewind(); $list->valid(); $list->next()) {
            $out .= "  " . $list->current() . "\n";
        }

        // ArrayObject
        $ao = new ArrayObject(['a' => 1, 'b' => 2]);
        $ao->append(3);
        $out .= "\nArrayObject count: " . $ao->count() . "\n";
        $out .= "ArrayObject['a']: " . $ao['a'] . "\n";

        // ArrayIterator
        $ai = new ArrayIterator(['x' => 10, 'y' => 20, 'z' => 30]);
        $out .= "\nArrayIterator:\n";
        while ($ai->valid()) {
            $out .= "  {$ai->key()} => {$ai->current()}\n";
            $ai->next();
        }

        // SplFileObject
        $tmpFile = sys_get_temp_dir() . '/spl_test.txt';
        file_put_contents($tmpFile, "line1\nline2\nline3\n");
        $file = new SplFileObject($tmpFile);
        $out .= "\nSplFileObject:\n";
        while (!$file->eof()) {
            $out .= "  " . trim($file->current()) . "\n";
            $file->next();
        }
        unlink($tmpFile);

        return $out;
    }
}

$lab = new SplLab();
echo $lab->process();