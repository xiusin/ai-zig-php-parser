<?php
class Queue {
    private array $items = [];
    private int $front = 0;

    public function enqueue(mixed $item): void {
        $this->items[] = $item;
    }

    public function dequeue(): mixed {
        if ($this->isEmpty()) return null;
        $item = $this->items[$this->front];
        $this->front++;
        if ($this->front > count($this->items) / 2) {
            $this->items = array_slice($this->items, $this->front);
            $this->front = 0;
        }
        return $item;
    }

    public function peek(): mixed {
        if ($this->isEmpty()) return null;
        return $this->items[$this->front];
    }

    public function isEmpty(): bool {
        return $this->front >= count($this->items);
    }

    public function size(): int {
        return count($this->items) - $this->front;
    }
}

$queue = new Queue();
$queue->enqueue('A');
$queue->enqueue('B');
$queue->enqueue('C');
echo $queue->dequeue() . "\n";
echo $queue->peek() . "\n";
echo $queue->size() . "\n";
$queue->enqueue('D');
echo $queue->dequeue() . "\n";
echo $queue->size() . "\n";
echo "OK\n";
