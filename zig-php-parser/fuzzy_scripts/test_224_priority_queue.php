<?php
class PriorityQueue {
    private array $heap = [];

    private function compare(mixed $a, mixed $b): int {
        return $a['priority'] <=> $b['priority'];
    }

    private function swap(int $i, int $j): void {
        [$this->heap[$i], $this->heap[$j]] = [$this->heap[$j], $this->heap[$i]];
    }

    private function bubbleUp(int $index): void {
        while ($index > 0) {
            $parent = (int)(($index - 1) / 2);
            if ($this->compare($this->heap[$index], $this->heap[$parent]) <= 0) break;
            $this->swap($index, $parent);
            $index = $parent;
        }
    }

    private function bubbleDown(int $index): void {
        $size = count($this->heap);
        while (true) {
            $smallest = $index;
            $left = 2 * $index + 1;
            $right = 2 * $index + 2;

            if ($left < $size && $this->compare($this->heap[$left], $this->heap[$smallest]) < 0) {
                $smallest = $left;
            }
            if ($right < $size && $this->compare($this->heap[$right], $this->heap[$smallest]) < 0) {
                $smallest = $right;
            }
            if ($smallest === $index) break;
            $this->swap($index, $smallest);
            $index = $smallest;
        }
    }

    public function enqueue(mixed $item, int $priority): void {
        $this->heap[] = ['item' => $item, 'priority' => $priority];
        $this->bubbleUp(count($this->heap) - 1);
    }

    public function dequeue(): mixed {
        if (empty($this->heap)) return null;
        $item = $this->heap[0]['item'];
        $last = array_pop($this->heap);
        if (!empty($this->heap)) {
            $this->heap[0] = $last;
            $this->bubbleDown(0);
        }
        return $item;
    }

    public function isEmpty(): bool {
        return empty($this->heap);
    }
}

$pq = new PriorityQueue();
$pq->enqueue('low priority task', 1);
$pq->enqueue('high priority task', 10);
$pq->enqueue('medium priority task', 5);

while (!$pq->isEmpty()) {
    echo $pq->dequeue() . "\n";
}
echo "OK\n";
