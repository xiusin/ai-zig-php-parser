<?php
// 极度混搭: 优先队列 + 堆实现 + 排序算法对比 + 性能计数 + 二叉搜索
echo "=== c013: PriorityQueue + Heap + SortCompare + PerfCount ===\n\n";

class MinHeap {
    private array $heap = [];
    private int $comparisons = 0;
    private int $swaps = 0;

    public function insert(int $value): void {
        $this->heap[] = $value;
        $this->siftUp(count($this->heap) - 1);
    }

    public function extractMin(): ?int {
        if (empty($this->heap)) return null;
        $min = $this->heap[0];
        $last = array_pop($this->heap);
        if (!empty($this->heap)) {
            $this->heap[0] = $last;
            $this->siftDown(0);
        }
        return $min;
    }

    public function peek(): ?int {
        return $this->heap[0] ?? null;
    }

    public function size(): int {
        return count($this->heap);
    }

    public function getStats(): array {
        return ['comparisons' => $this->comparisons, 'swaps' => $this->swaps];
    }

    private function siftUp(int $idx): void {
        while ($idx > 0) {
            $parent = intdiv($idx - 1, 2);
            $this->comparisons++;
            if ($this->heap[$idx] < $this->heap[$parent]) {
                $this->swap($idx, $parent);
                $idx = $parent;
            } else {
                break;
            }
        }
    }

    private function siftDown(int $idx): void {
        $n = count($this->heap);
        while (true) {
            $left = 2 * $idx + 1;
            $right = 2 * $idx + 2;
            $smallest = $idx;

            if ($left < $n) {
                $this->comparisons++;
                if ($this->heap[$left] < $this->heap[$smallest]) {
                    $smallest = $left;
                }
            }
            if ($right < $n) {
                $this->comparisons++;
                if ($this->heap[$right] < $this->heap[$smallest]) {
                    $smallest = $right;
                }
            }
            if ($smallest !== $idx) {
                $this->swap($idx, $smallest);
                $idx = $smallest;
            } else {
                break;
            }
        }
    }

    private function swap(int $a, int $b): void {
        $this->swaps++;
        $temp = $this->heap[$a];
        $this->heap[$a] = $this->heap[$b];
        $this->heap[$b] = $temp;
    }
}

class PriorityQueue {
    private MinHeap $heap;

    public function __construct() {
        $this->heap = new MinHeap();
    }

    public function enqueue(int $priority): void {
        $this->heap->insert($priority);
    }

    public function dequeue(): ?int {
        return $this->heap->extractMin();
    }

    public function peek(): ?int {
        return $this->heap->peek();
    }

    public function isEmpty(): bool {
        return $this->heap->size() === 0;
    }

    public function size(): int {
        return $this->heap->size();
    }
}

class SortingBenchmark {
    public static function bubbleSort(array $arr): array {
        $n = count($arr);
        for ($i = 0; $i < $n; $i++) {
            for ($j = 0; $j < $n - $i - 1; $j++) {
                if ($arr[$j] > $arr[$j + 1]) {
                    $temp = $arr[$j];
                    $arr[$j] = $arr[$j + 1];
                    $arr[$j + 1] = $temp;
                }
            }
        }
        return $arr;
    }

    public static function insertionSort(array $arr): array {
        $n = count($arr);
        for ($i = 1; $i < $n; $i++) {
            $key = $arr[$i];
            $j = $i - 1;
            while ($j >= 0 && $arr[$j] > $key) {
                $arr[$j + 1] = $arr[$j];
                $j--;
            }
            $arr[$j + 1] = $key;
        }
        return $arr;
    }

    public static function selectionSort(array $arr): array {
        $n = count($arr);
        for ($i = 0; $i < $n; $i++) {
            $minIdx = $i;
            for ($j = $i + 1; $j < $n; $j++) {
                if ($arr[$j] < $arr[$minIdx]) {
                    $minIdx = $j;
                }
            }
            if ($minIdx !== $i) {
                $temp = $arr[$i];
                $arr[$i] = $arr[$minIdx];
                $arr[$minIdx] = $temp;
            }
        }
        return $arr;
    }

    public static function mergeSort(array $arr): array {
        $n = count($arr);
        if ($n <= 1) return $arr;
        $mid = intdiv($n, 2);
        $left = self::mergeSort(array_slice($arr, 0, $mid));
        $right = self::mergeSort(array_slice($arr, $mid));
        return self::merge($left, $right);
    }

    private static function merge(array $left, array $right): array {
        $result = [];
        $i = $j = 0;
        while ($i < count($left) && $j < count($right)) {
            if ($left[$i] <= $right[$j]) {
                $result[] = $left[$i++];
            } else {
                $result[] = $right[$j++];
            }
        }
        while ($i < count($left)) $result[] = $left[$i++];
        while ($j < count($right)) $result[] = $right[$j++];
        return $result;
    }

    public static function heapSort(array $arr): array {
        $heap = new MinHeap();
        foreach ($arr as $v) {
            $heap->insert($v);
        }
        $result = [];
        while (($min = $heap->extractMin()) !== null) {
            $result[] = $min;
        }
        return $result;
    }
}

// === 测试 ===

echo "--- Priority Queue ---\n";
$pq = new PriorityQueue();
$pq->enqueue(5);
$pq->enqueue(1);
$pq->enqueue(3);
$pq->enqueue(7);
$pq->enqueue(2);

echo "Size: " . $pq->size() . "\n";
echo "Peek: " . $pq->peek() . "\n";
$extracted = [];
while (!$pq->isEmpty()) {
    $extracted[] = $pq->dequeue();
}
echo "Extracted: " . implode(",", $extracted) . "\n";

echo "\n--- Heap Stats ---\n";
$heap = new MinHeap();
$data = [64, 25, 12, 22, 11, 9, 5, 3, 7, 1];
foreach ($data as $v) {
    $heap->insert($v);
}
$sorted = [];
while (($min = $heap->extractMin()) !== null) {
    $sorted[] = $min;
}
$stats = $heap->getStats();
echo "HeapSort result: " . implode(",", $sorted) . "\n";
echo "Comparisons: {$stats['comparisons']}, Swaps: {$stats['swaps']}\n";

echo "\n--- Sorting Comparison ---\n";
$data = [38, 27, 43, 3, 9, 82, 10, 15, 52, 6, 47, 91, 33, 28];

$sortedBubble = SortingBenchmark::bubbleSort($data);
$sortedInsert = SortingBenchmark::insertionSort($data);
$sortedSelect = SortingBenchmark::selectionSort($data);
$sortedMerge = SortingBenchmark::mergeSort($data);
$sortedHeap = SortingBenchmark::heapSort($data);

echo "Bubble:    " . implode(",", $sortedBubble) . "\n";
echo "Insertion: " . implode(",", $sortedInsert) . "\n";
echo "Selection: " . implode(",", $sortedSelect) . "\n";
echo "Merge:     " . implode(",", $sortedMerge) . "\n";
echo "Heap:      " . implode(",", $sortedHeap) . "\n";

// Verify all produce the same result
$reference = $sortedBubble;
$allMatch = $sortedInsert === $reference && $sortedSelect === $reference
    && $sortedMerge === $reference && $sortedHeap === $reference;
echo "All sort results identical: " . var_export($allMatch, true) . "\n";

echo "\n--- Edge Cases ---\n";
echo "Empty sort: " . implode(",", SortingBenchmark::mergeSort([])) . "\n";
echo "Single: " . implode(",", SortingBenchmark::mergeSort([42])) . "\n";
echo "Two sorted: " . implode(",", SortingBenchmark::mergeSort([1, 2])) . "\n";
echo "Two reverse: " . implode(",", SortingBenchmark::mergeSort([2, 1])) . "\n";
echo "Duplicates: " . implode(",", SortingBenchmark::mergeSort([5, 5, 5, 5, 5])) . "\n";
echo "Negative: " . implode(",", SortingBenchmark::mergeSort([-3, -1, -4, -1, -5])) . "\n";

echo "\n=== c013 Done ===\n";
