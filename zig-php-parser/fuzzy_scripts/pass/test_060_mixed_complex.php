<?php
// 测试60: 迭代器组合
class RangeIterator implements Iterator {
    private $start, $end, $current;
    
    public function __construct(int $start, int $end) {
        $this->start = $start;
        $this->end = $end;
    }
    
    public function current(): int {
        return $this->current;
    }
    
    public function key(): int {
        return $this->current - $this->start;
    }
    
    public function next(): void {
        $this->current++;
    }
    
    public function rewind(): void {
        $this->current = $this->start;
    }
    
    public function valid(): bool {
        return $this->current <= $this->end;
    }
}

// 过滤器迭代器
class EvenFilter extends FilterIterator {
    public function accept(): bool {
        return $this->current() % 2 === 0;
    }
}

// 限制迭代器
$range = new RangeIterator(1, 20);
$evenRange = new EvenFilter($range);
$limited = new LimitIterator($evenRange, 0, 5);

echo "Even numbers (first 5):\n";
foreach ($limited as $num) {
    echo "  $num\n";
}

// 缓存迭代器
$arrayIter = new ArrayIterator([1, 2, 3, 4, 5]);
$cached = new CachingIterator($arrayIter);

echo "Cached iteration:\n";
foreach ($cached as $value) {
    echo "  Current: $value";
    if ($cached->hasNext()) {
        echo " (next: " . $cached->getInnerIterator()->current() . ")";
    }
    echo "\n";
}

// 递归迭代器
$tree = [
    'root' => [
        'child1' => ['leaf1', 'leaf2'],
        'child2' => ['leaf3'],
    ],
];
$recursive = new RecursiveArrayIterator($tree);
$flat = new RecursiveIteratorIterator($recursive);

echo "Flattened tree:\n";
foreach ($flat as $leaf) {
    echo "  $leaf\n";
}

// 追加迭代器
$iter1 = new ArrayIterator([1, 2, 3]);
$iter2 = new ArrayIterator([4, 5, 6]);
$appended = new AppendIterator();
$appended->append($iter1);
$appended->append($iter2);

echo "Appended iterators:\n";
foreach ($appended as $value) {
    echo "  $value\n";
}

// 正则迭代器
$names = new ArrayIterator(["Alice", "Bob", "Charlie", "Diana"]);
$aNames = new RegexIterator($names, '/^A/');

echo "Names starting with A:\n";
foreach ($aNames as $name) {
    echo "  $name\n";
}
?>