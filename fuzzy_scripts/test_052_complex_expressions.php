<?php
// 复杂表达式测试

// 复杂算术表达式
$a = 10;
$b = 5;
$c = 3;
$result = (($a + $b) * $c - $a / $b) ** 2;
echo "Complex arithmetic: $result\n";

// 复杂比较表达式
$x = 5;
$y = 10;
$z = 15;
$complex = ($x < $y && $y < $z) || ($x === $y && $z > $x);
echo "Complex comparison: " . var_export($complex, true) . "\n";

// 三元表达式嵌套
$score = 75;
$grade = $score >= 90 ? 'A' :
         ($score >= 80 ? 'B' :
         ($score >= 70 ? 'C' :
         ($score >= 60 ? 'D' : 'F')));
echo "Grade: $grade\n";

// 空合并链
$value = null;
$fallback1 = null;
$fallback2 = 'final value';
$result = $value ?? $fallback1 ?? $fallback2 ?? 'never reached';
echo "Null coalesce chain: $result\n";

// Elvis链
$val = 0;
$elvisResult = $val ?: 'default1' ?: 'default2';
echo "Elvis chain: $elvisResult\n";

// 复杂数组表达式
$arr = [1, 2, 3, 4, 5];
$result = array_sum(array_map(fn($x) => $x * $x, array_filter($arr, fn($x) => $x > 2)));
echo "Array pipeline: $result\n";

// 字符串拼接链
$parts = ['Hello', 'World', 'PHP', '8'];
$joined = implode(' ', array_map('strtoupper', $parts));
echo "Joined string: $joined\n";

// 正则匹配链
$text = "The quick brown fox jumps over the lazy dog";
$words = preg_split('/\s+/', preg_replace('/[^a-z\s]/i', '', $text));
echo "Word count: " . count($words) . "\n";

// 复杂条件表达式
$status = 'active';
$role = 'admin';
$access = match(true) {
    $status === 'active' && $role === 'admin' => 'Full access',
    $status === 'active' && $role === 'user' => 'Limited access',
    $status === 'inactive' => 'No access',
    default => 'Unknown'
};
echo "Access: $access\n";

// 复杂类型转换链
$mixed = "42.5 apples";
$result = (int)(float)$mixed;
echo "Type cast chain: $result\n";

// 位运算链
$flags = 0b0000;
$flags |= 0b0001; // 设置位1
$flags |= 0b0100; // 设置位3
$flags &= ~0b0001; // 清除位1
$flags ^= 0b1000; // 切换位4
echo "Flags: " . decbin($flags) . "\n";

// 复杂数组解构
$data = [
    'user' => [
        'name' => 'Alice',
        'scores' => [85, 90, 78]
    ],
    'meta' => ['version' => 1]
];

['user' => ['name' => $name, 'scores' => [$first, $second]]] = $data;
echo "Destructured: $name has scores $first, $second\n";

// 箭头函数链
$transform = fn($x) => $x * 2;
$addOne = fn($x) => $x + 1;
$square = fn($x) => $x * $x;

$pipeline = fn($x) => $square($addOne($transform($x)));
echo "Pipeline result: " . $pipeline(5) . "\n";

// 复杂match表达式
$type = 'premium';
$months = 12;
$discount = match([$type, $months]) {
    ['basic', $m] if $m >= 12 => 0.10,
    ['basic', _] => 0,
    ['premium', $m] if $m >= 6 => 0.15,
    ['premium', _] => 0.05,
    ['enterprise', _] => 0.20,
    default => 0
};
echo "Discount: " . ($discount * 100) . "%\n";

// 复杂对象表达式
class Calculator {
    public function __construct(private int $value) {}

    public function add(int $n): self { return new self($this->value + $n); }
    public function multiply(int $n): self { return new self($this->value * $n); }
    public function subtract(int $n): self { return new self($this->value - $n); }
    public function get(): int { return $this->value; }
}

$result = (new Calculator(10))->add(5)->multiply(2)->subtract(3)->get();
echo "Fluent result: $result\n";

echo "Complex expressions tests completed\n";
