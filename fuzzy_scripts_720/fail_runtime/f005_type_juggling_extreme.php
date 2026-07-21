<?php
// 极度混搭: 类型自动转换极限测试 + 运算符重载行为 + 比较运算 + 边界值
echo "=== f005: Type Juggling Extreme + Comparison + Boundary ===\n";

// 数值与字符串转换
$tests = [
    "10" + 20,
    "10" . 20,
    "10abc" + 5,
    3.14 * "2",
    "0" == false,
    "" == false,
    "0" == 0,
    "abc" == 0,
    null == false,
    null === null,
    [] == false,
    [0] == false,
    "1e1" == 10,
    "10" === 10,
    10 === 10,
    10.0 === 10,
    10.0 == 10,
    PHP_INT_MAX + 1,
    (int)"2147483648",
    (float)"1.5e3",
    (bool)"0",
    (bool)"",
    (bool)"0.0",
    (bool)0,
    (bool)0.0,
    (bool)[],
    (bool)[0],
    (int)true,
    (int)false,
    (int)3.99,
    (int)-3.99,
    (string)0.0,
    (string)true,
    (array)"hello",
    (array)42,
    (array)null,
];

foreach ($tests as $i => $val) {
    $type = gettype($val);
    $display = match($type) {
        'bool' => var_export($val, true),
        'array' => json_encode($val),
        'float', 'integer' => (string)$val,
        'string' => "'$val'",
        default => (string)$val,
    };
    echo "test[" . sprintf('%02d', $i) . "]: $display ($type)\n";
}

// 复杂运算链
$a = "5";
$b = 3;
$c = $a + $b;        // 8 (int)
$d = $a . $b;        // "53" (string)
$e = $c . $d;        // "853" (string)
$f = $e + 100;       // 953 (int)
$g = $f / 2;         // 476.5 (float)
$h = (int)$g;        // 476 (int)
$i = $h % 10;        // 6 (int)
$j = $i ** 3;        // 216 (int)

echo "\nChain: a='$a' b=$b c=$c d='$d' e='$e' f=$f g=$g h=$h i=$i j=$j\n";
echo "Types: " . gettype($c) . ", " . gettype($d) . ", " . gettype($e) . ", " . gettype($f) . ", " . gettype($g) . "\n";

// 太空船操作符
echo "\nSpaceship:\n";
$pairs = [[1, 2], [2, 1], [1, 1], ['a', 'b'], [10, '9'], ['10', 10], [1.5, 1.5]];
foreach ($pairs as [$x, $y]) {
    echo "  " . var_export($x, true) . " <=> " . var_export($y, true) . " = " . ($x <=> $y) . "\n";
}

// 位运算
echo "\nBitwise:\n";
echo "  5 & 3 = " . (5 & 3) . "\n";
echo "  5 | 3 = " . (5 | 3) . "\n";
echo "  5 ^ 3 = " . (5 ^ 3) . "\n";
echo "  ~5 = " . (~5) . "\n";
echo "  5 << 2 = " . (5 << 2) . "\n";
echo "  20 >> 2 = " . (20 >> 2) . "\n";

// 增减运算符
echo "\nIncrement/Decrement:\n";
$x = 5;
echo "  x++ = " . ($x++) . " (after: $x)\n";
echo "  ++x = " . (++$x) . " (after: $x)\n";
echo "  x-- = " . ($x--) . " (after: $x)\n";
echo "  --x = " . (--$x) . " (after: $x)\n";

$str = 'a';
echo "  str++ = " . ($str++) . " (after: $str)\n";
$str = 'Z';
echo "  str++ from Z = " . (++$str) . "\n";

// 三元与null合并
echo "\nTernary & Null coalescing:\n";
$data = ['a' => 1, 'b' => null, 'c' => 0];
echo "  a: " . ($data['a'] ?? 'default') . "\n";
echo "  b: " . ($data['b'] ?? 'default') . "\n";
echo "  d: " . ($data['d'] ?? 'default') . "\n";
echo "  a ternary: " . ($data['a'] ? 'yes' : 'no') . "\n";
echo "  c ternary: " . ($data['c'] ? 'yes' : 'no') . "\n";
echo "  b ?: 'fallback': " . ($data['b'] ?? 'fallback') . "\n";

echo "=== f005 Done ===\n";
