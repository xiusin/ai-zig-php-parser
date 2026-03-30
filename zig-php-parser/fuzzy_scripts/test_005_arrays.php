<?php
// Test 005: Array operations, sorting, and complex transformations
class ArrayLab {
    public function __construct(private array $data) {}

    public function process(): string {
        $out = "";

        // Basic array operations
        $out .= "Count: " . count($this->data) . "\n";
        $out .= "Is array: " . (is_array($this->data) ? 'yes' : 'no') . "\n";
        $out .= "Is list: " . (array_is_list($this->data) ? 'yes' : 'no') . "\n";

        // Keys and values
        $out .= "Keys: " . implode(',', array_keys($this->data)) . "\n";
        $out .= "Values: " . implode(',', array_values($this->data)) . "\n";

        // Array diff/intersect
        $arr2 = ['a', 'b', 'c'];
        $out .= "Diff with [a,b,c]: " . implode(',', array_diff($this->data, $arr2)) . "\n";
        $out .= "Intersect with [a,b,c]: " . implode(',', array_intersect($this->data, $arr2)) . "\n";

        // Filtering
        $filtered = array_filter($this->data, fn($v) => is_numeric($v) && $v > 2);
        $out .= "Filtered (numeric > 2): " . implode(',', $filtered) . "\n";

        // Mapping
        $mapped = array_map(fn($v) => $v * 2, $this->data);
        $out .= "Mapped (*2): " . implode(',', $mapped) . "\n";

        // Reduction
        $sum = array_reduce($this->data, fn($c, $v) => $c + $v, 0);
        $out .= "Sum: $sum\n";

        // Sorting
        $sorted = $this->data;
        sort($sorted);
        $out .= "Sorted: " . implode(',', $sorted) . "\n";

        rsort($sorted);
        $out .= "RSorted: " . implode(',', $sorted) . "\n";

        // Associative sort
        $assoc = ['c' => 3, 'a' => 1, 'b' => 2];
        asort($assoc);
        $out .= "Asort: " . json_encode($assoc) . "\n";

        ksort($assoc);
        $out .= "Ksort: " . json_encode($assoc) . "\n";

        // Array push/pop/shift
        $stack = $this->data;
        array_push($stack, 100);
        $out .= "After push(100): " . implode(',', $stack) . "\n";

        $popped = array_pop($stack);
        $out .= "Popped: $popped, Remaining: " . implode(',', $stack) . "\n";

        array_unshift($stack, 0);
        $out .= "After unshift(0): " . implode(',', $stack) . "\n";

        $shifted = array_shift($stack);
        $out .= "Shifted: $shifted, Remaining: " . implode(',', $stack) . "\n";

        // Array slice
        $out .= "Slice [1:3]: " . implode(',', array_slice($this->data, 1, 2)) . "\n";

        // Array splice
        $splice_arr = ['a', 'b', 'c', 'd'];
        array_splice($splice_arr, 1, 2, ['x', 'y']);
        $out .= "Splice [1:2 -> x,y]: " . implode(',', $splice_arr) . "\n";

        // Array merge
        $merged = array_merge($this->data, [100, 200, 300]);
        $out .= "Merged with [100,200,300]: " . implode(',', $merged) . "\n";

        // Array chunk
        $chunked = array_chunk($this->data, 2);
        $out .= "Chunk by 2: " . count($chunked) . " chunks\n";

        // Array fill
        $filled = array_fill(0, 3, 'filled');
        $out .= "Array_fill(0,3,'filled'): " . implode(',', $filled) . "\n";

        // Range
        $range = range(1, 5);
        $out .= "Range(1,5): " . implode(',', $range) . "\n";

        // Shuffle
        $shuffled = $this->data;
        shuffle($shuffled);
        $out .= "Shuffled: " . implode(',', $shuffled) . "\n";

        return $out;
    }

    public function processDeep(): string {
        $out = "";

        // Nested arrays
        $nested = [
            'a' => [1, 2, 3],
            'b' => ['x' => 10, 'y' => 20],
            'c' => [[1, 2], [3, 4]],
        ];

        $out .= "Nested count: " . count($nested) . "\n";
        $out .= "Nested['a'] count: " . count($nested['a']) . "\n";
        $out .= "Deep access nested['c'][0][1]: " . $nested['c'][0][1] . "\n";

        // Array_walk
        $walk_result = [];
        array_walk($nested['a'], function($v, $k) use (&$walk_result) {
            $walk_result[$k] = $v * 10;
        });
        $out .= "Array_walk result: " . implode(',', $walk_result) . "\n";

        // Array_reduce recursive
        $flat = array_reduce($nested, fn($c, $v) => array_merge($c, (array)$v), []);
        $out .= "Flattened: " . implode(',', $flat) . "\n";

        return $out;
    }
}

$tests = [
    [1, 2, 3, 4, 5],
    ['a', 'b', 'c'],
    [5, 3, 1, 4, 2],
    [],
    [1],
];

foreach ($tests as $i => $data) {
    echo "=== Test $i: " . json_encode($data) . " ===\n";
    $lab = new ArrayLab($data);
    echo $lab->process();
    echo "\n";
}

echo "=== Deep Operations ===\n";
$lab = new ArrayLab([1, 2, 3]);
echo $lab->processDeep();