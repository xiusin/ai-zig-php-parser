<?php
// SPL迭代器测试

// ArrayIterator
$arr = new ArrayIterator(['a', 'b', 'c', 'd']);
echo "ArrayIterator:\n";
foreach ($arr as $key => $value) {
    echo "  $key => $value\n";
}

// 迭代器方法
$arr->rewind();
while ($arr->valid()) {
    echo "  current: " . $arr->current() . "\n";
    $arr->next();
}

// DirectoryIterator (使用临时目录)
$tempDir = sys_get_temp_dir();
echo "DirectoryIterator on temp dir:\n";
$dir = new DirectoryIterator($tempDir);
$count = 0;
foreach ($dir as $file) {
    if ($count++ >= 3) break;
    if (!$file->isDot()) {
        echo "  " . $file->getFilename() . "\n";
    }
}

// FilterIterator
class EvenFilter extends FilterIterator {
    public function accept(): bool {
        return $this->current() % 2 === 0;
    }
}

$numbers = new ArrayIterator([1, 2, 3, 4, 5, 6, 7, 8, 9, 10]);
$even = new EvenFilter($numbers);
echo "EvenFilter:\n";
foreach ($even as $num) {
    echo "  $num\n";
}

// LimitIterator
$all = new ArrayIterator(range('a', 'z'));
$limited = new LimitIterator($all, 5, 5);
echo "LimitIterator (5-9):\n";
foreach ($limited as $char) {
    echo "  $char\n";
}

// IteratorIterator
$arrayIterator = new ArrayIterator(['x', 'y', 'z']);
$iteratorIterator = new IteratorIterator($arrayIterator);
echo "IteratorIterator:\n";
foreach ($iteratorIterator as $val) {
    echo "  $val\n";
}

// RecursiveArrayIterator
$nested = [
    'a' => 1,
    'b' => [
        'c' => 2,
        'd' => [
            'e' => 3
        ]
    ]
];

$recursiveIterator = new RecursiveIteratorIterator(
    new RecursiveArrayIterator($nested),
    RecursiveIteratorIterator::LEAVES_ONLY
);
echo "RecursiveIteratorIterator:\n";
foreach ($recursiveIterator as $key => $value) {
    echo "  $key => $value\n";
}

// CachingIterator
$caching = new CachingIterator(new ArrayIterator([1, 2, 3]));
echo "CachingIterator:\n";
$values = [];
foreach ($caching as $val) {
    $values[] = $val;
}
echo "  cached: " . implode(', ', $values) . "\n";

// InfiniteIterator
$inf = new InfiniteIterator(new ArrayIterator(['a', 'b', 'c']));
echo "InfiniteIterator (limited):\n";
$count = 0;
foreach ($inf as $val) {
    echo "  $val\n";
    if (++$count >= 6) break;
}

// NoRewindIterator
$noRewind = new NoRewindIterator(new ArrayIterator([1, 2, 3]));
echo "NoRewindIterator first pass:\n";
foreach ($noRewind as $val) {
    echo "  $val\n";
}
// 第二次遍历不会输出任何内容
echo "NoRewindIterator second pass:\n";
foreach ($noRewind as $val) {
    echo "  $val (should not appear)\n";
}

// AppendIterator
$append = new AppendIterator();
$append->append(new ArrayIterator([1, 2]));
$append->append(new ArrayIterator([3, 4]));
$append->append(new ArrayIterator([5, 6]));
echo "AppendIterator:\n";
foreach ($append as $val) {
    echo "  $val\n";
}

// MultipleIterator
$multiple = new MultipleIterator(MultipleIterator::MIT_KEYS_ASSOC);
$multiple->attachIterator(new ArrayIterator([1, 2, 3]), 'a');
$multiple->attachIterator(new ArrayIterator(['x', 'y', 'z']), 'b');
echo "MultipleIterator:\n";
foreach ($multiple as $pair) {
    echo "  a={$pair['a']}, b={$pair['b']}\n";
}

echo "SPL Iterator tests completed\n";
