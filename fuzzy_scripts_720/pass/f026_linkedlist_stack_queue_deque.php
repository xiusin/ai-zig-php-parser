<?php
// 极度混搭: 链表 + 栈 + 队列 + 双端队列 + 环形缓冲区
echo "=== f026: LinkedList + Stack + Queue + Deque + RingBuffer ===\n";

class LinkedListNode {
    public function __construct(public mixed $data, public ?LinkedListNode $next = null) {}
}

class LinkedList {
    private ?LinkedListNode $head = null;
    private ?LinkedListNode $tail = null;
    private int $size = 0;

    public function push(mixed $data): void {
        $node = new LinkedListNode($data);
        if ($this->tail === null) {
            $this->head = $this->tail = $node;
        } else {
            $this->tail->next = $node;
            $this->tail = $node;
        }
        $this->size++;
    }

    public function unshift(mixed $data): void {
        $this->head = new LinkedListNode($data, $this->head);
        if ($this->tail === null) $this->tail = $this->head;
        $this->size++;
    }

    public function pop(): mixed {
        if ($this->head === null) return null;
        if ($this->head === $this->tail) {
            $data = $this->head->data;
            $this->head = $this->tail = null;
            $this->size--;
            return $data;
        }
        $node = $this->head;
        while ($node->next !== $this->tail) $node = $node->next;
        $data = $this->tail->data;
        $node->next = null;
        $this->tail = $node;
        $this->size--;
        return $data;
    }

    public function shift(): mixed {
        if ($this->head === null) return null;
        $data = $this->head->data;
        $this->head = $this->head->next;
        if ($this->head === null) $this->tail = null;
        $this->size--;
        return $data;
    }

    public function toArray(): array {
        $result = [];
        $node = $this->head;
        while ($node !== null) { $result[] = $node->data; $node = $node->next; }
        return $result;
    }

    public function size(): int { return $this->size; }
    public function isEmpty(): bool { return $this->size === 0; }

    public function reverse(): void {
        $prev = null;
        $current = $this->head;
        $this->tail = $this->head;
        while ($current !== null) {
            $next = $current->next;
            $current->next = $prev;
            $prev = $current;
            $current = $next;
        }
        $this->head = $prev;
    }

    public function find(callable $fn): mixed {
        $node = $this->head;
        $index = 0;
        while ($node !== null) {
            if ($fn($node->data, $index)) return $node->data;
            $node = $node->next;
            $index++;
        }
        return null;
    }
}

class Stack {
    private array $items = [];
    public function push(mixed $item): void { $this->items[] = $item; }
    public function pop(): mixed { return array_pop($this->items); }
    public function peek(): mixed { return $this->items[count($this->items) - 1] ?? null; }
    public function size(): int { return count($this->items); }
    public function isEmpty(): bool { return empty($this->items); }
    public function toArray(): array { return $this->items; }
}

class Queue {
    private array $items = [];
    public function enqueue(mixed $item): void { $this->items[] = $item; }
    public function dequeue(): mixed { return array_shift($this->items); }
    public function front(): mixed { return $this->items[0] ?? null; }
    public function size(): int { return count($this->items); }
    public function isEmpty(): bool { return empty($this->items); }
}

class Deque {
    private array $items = [];
    public function pushLeft(mixed $item): void { array_unshift($this->items, $item); }
    public function pushRight(mixed $item): void { $this->items[] = $item; }
    public function popLeft(): mixed { return array_shift($this->items); }
    public function popRight(): mixed { return array_pop($this->items); }
    public function size(): int { return count($this->items); }
    public function isEmpty(): bool { return empty($this->items); }
    public function toArray(): array { return $this->items; }
}

class RingBuffer {
    private array $buffer;
    private int $head = 0;
    private int $tail = 0;
    private int $count = 0;
    private int $capacity;

    public function __construct(int $capacity) {
        $this->capacity = $capacity;
        $this->buffer = array_fill(0, $capacity, null);
    }

    public function push(mixed $item): bool {
        if ($this->count === $this->capacity) return false;
        $this->buffer[$this->tail] = $item;
        $this->tail = ($this->tail + 1) % $this->capacity;
        $this->count++;
        return true;
    }

    public function pop(): mixed {
        if ($this->count === 0) return null;
        $item = $this->buffer[$this->head];
        $this->buffer[$this->head] = null;
        $this->head = ($this->head + 1) % $this->capacity;
        $this->count--;
        return $item;
    }

    public function isFull(): bool { return $this->count === $this->capacity; }
    public function isEmpty(): bool { return $this->count === 0; }
    public function size(): int { return $this->count; }
    public function toArray(): array {
        $result = [];
        for ($i = 0; $i < $this->count; $i++) {
            $result[] = $this->buffer[($this->head + $i) % $this->capacity];
        }
        return $result;
    }
}

// === 测试 ===
echo "--- LinkedList ---\n";
$list = new LinkedList();
foreach ([1, 2, 3, 4, 5] as $v) $list->push($v);
echo "List: " . implode(' -> ', $list->toArray()) . "\n";
$list->unshift(0);
echo "After unshift(0): " . implode(' -> ', $list->toArray()) . "\n";
echo "Pop: " . $list->pop() . "\n";
echo "Shift: " . $list->shift() . "\n";
echo "List: " . implode(' -> ', $list->toArray()) . "\n";
$list->reverse();
echo "Reversed: " . implode(' -> ', $list->toArray()) . "\n";
echo "Find >3: " . $list->find(fn($v) => $v > 3) . "\n";
echo "Size: " . $list->size() . "\n";

echo "\n--- Stack ---\n";
$stack = new Stack();
foreach ([1, 2, 3] as $v) $stack->push($v);
echo "Stack: " . implode(',', $stack->toArray()) . "\n";
echo "Peek: " . $stack->peek() . "\n";
echo "Pop: " . $stack->pop() . "\n";
echo "Pop: " . $stack->pop() . "\n";
echo "Size: " . $stack->size() . "\n";

echo "\n--- Queue ---\n";
$queue = new Queue();
foreach (['A', 'B', 'C'] as $v) $queue->enqueue($v);
echo "Front: " . $queue->front() . "\n";
echo "Dequeue: " . $queue->dequeue() . "\n";
echo "Dequeue: " . $queue->dequeue() . "\n";
echo "Size: " . $queue->size() . "\n";

echo "\n--- Deque ---\n";
$deque = new Deque();
$deque->pushRight(1);
$deque->pushRight(2);
$deque->pushLeft(0);
echo "Deque: " . implode(',', $deque->toArray()) . "\n";
echo "PopLeft: " . $deque->popLeft() . "\n";
echo "PopRight: " . $deque->popRight() . "\n";
echo "Deque: " . implode(',', $deque->toArray()) . "\n";

echo "\n--- RingBuffer ---\n";
$ring = new RingBuffer(3);
foreach ([1, 2, 3] as $v) {
    $ring->push($v);
    echo "Push $v → size=" . $ring->size() . "\n";
}
echo "Is full: " . var_export($ring->isFull(), true) . "\n";
echo "Push 4 (should fail): " . var_export($ring->push(4), true) . "\n";
echo "Pop: " . $ring->pop() . "\n";
echo "Push 4: " . var_export($ring->push(4), true) . "\n";
echo "Buffer: " . implode(',', $ring->toArray()) . "\n";

echo "=== f026 Done ===\n";
