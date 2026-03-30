<?php
// 测试66: SPL迭代器全面测试 - Filter, Limit, Append, Caching
// 测试目的：验证SPL迭代器组合和高级用法

// 基础数据
$data = range(1, 100);

// ArrayIterator基础
$iterator = new ArrayIterator($data);

// LimitIterator - 限制迭代范围
$limited = new LimitIterator($iterator, 10, 5);
echo "Limited (10-14): " . implode(', ', iterator_to_array($limited)) . "\n";

// FilterIterator - 自定义过滤
class EvenFilter extends FilterIterator {
    public function accept(): bool {
        return $this->current() % 2 === 0;
    }
}

$evens = new EvenFilter($iterator);
$evensLimited = new LimitIterator($evens, 0, 5);
echo "First 5 evens: " . implode(', ', iterator_to_array($evensLimited)) . "\n";

// CachingIterator - 预览下一个元素
$caching = new CachingIterator($iterator, CachingIterator::FULL_CACHE);
$firstThree = [];
foreach ($caching as $value) {
    $firstThree[] = $value;
    if (count($firstThree) >= 3) break;
}
echo "Cached first 3: " . implode(', ', $firstThree) . "\n";
echo "Cache count: " . count($caching->getCache()) . "\n";

// AppendIterator - 合并多个迭代器
$append = new AppendIterator();
$append->append(new ArrayIterator([1, 2, 3]));
$append->append(new ArrayIterator(['a', 'b', 'c']));
$append->append(new ArrayIterator([true, false]));
echo "Appended: " . implode(', ', iterator_to_array($append)) . "\n";

// RegexIterator - 正则过滤
$words = new ArrayIterator(['apple', 'banana', 'cherry', 'apricot', 'blueberry']);
$aWords = new RegexIterator($words, '/^a/');
echo "Words starting with 'a': " . implode(', ', iterator_to_array($aWords)) . "\n";

// RecursiveArrayIterator + RecursiveIteratorIterator
$nested = [
    'level1' => [
        'level2' => [
            'level3' => ['a', 'b', 'c']
        ],
        'other' => 'value'
    ]
];
$recursive = new RecursiveArrayIterator($nested);
$flat = new RecursiveIteratorIterator($recursive);
echo "Flattened: " . implode(', ', iterator_to_array($flat)) . "\n";

// 带深度的递归迭代
$deep = new RecursiveIteratorIterator($recursive, RecursiveIteratorIterator::SELF_FIRST);
echo "With depth:\n";
foreach ($deep as $key => $value) {
    echo str_repeat("  ", $deep->getDepth()) . "$key: ";
    echo is_array($value) ? "[array]" : $value;
    echo "\n";
}

// 自定义迭代器实现
class RangeIterator implements Iterator {
    private int $start, $end, $current;
    
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

$range = new RangeIterator(5, 10);
echo "Range 5-10: " . implode(', ', iterator_to_array($range)) . "\n";

// 迭代器与生成器组合
function squareGenerator(Iterator $iterator): Generator {
    foreach ($iterator as $value) {
        yield $value * $value;
    }
}

$squares = squareGenerator(new ArrayIterator([1, 2, 3, 4, 5]));
echo "Squares: " . implode(', ', iterator_to_array($squares)) . "\n";
?>
