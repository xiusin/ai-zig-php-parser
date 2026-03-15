<?php
// 测试52: PHP 8.1 first-class callable syntax - 方法引用作为回调
// 测试目的：验证MyClass::method(...)语法创建闭包

class StringProcessor {
    public function __construct(private string $prefix = '') {}
    
    public function wrap(string $input): string {
        return "[{$this->prefix}] $input";
    }
    
    public static function upper(string $input): string {
        return strtoupper($input);
    }
    
    public static function lower(string $input): string {
        return strtolower($input);
    }
}

$words = ['hello', 'WORLD', 'MiXeD'];

// 静态方法引用
$upperFn = StringProcessor::upper(...);
$lowerFn = StringProcessor::lower(...);

echo "Upper: " . implode(', ', array_map($upperFn, $words)) . "\n";
echo "Lower: " . implode(', ', array_map($lowerFn, $words)) . "\n";

// 实例方法引用（自动绑定$this）
$processor = new StringProcessor('TAG');
$wrapFn = $processor->wrap(...);

echo "Wrapped:\n";
foreach ($words as $word) {
    echo "  " . $wrapFn($word) . "\n";
}

// 与usort结合
$numbers = [5, 2, 8, 1, 9];
$compareDesc = fn($a, $b) => $b <=> $a;
usort($numbers, $compareDesc);
echo "Sorted desc: " . implode(', ', $numbers) . "\n";

// 内置函数引用
$lengths = array_map(strlen(...), $words);
echo "Lengths: " . implode(', ', $lengths) . "\n";

// 复杂链式处理
class Pipeline {
    private array $steps = [];
    
    public function add(callable $fn): self {
        $this->steps[] = $fn;
        return $this;
    }
    
    public function process($input) {
        return array_reduce($this->steps, fn($carry, $fn) => $fn($carry), $input);
    }
}

$pipeline = (new Pipeline())
    ->add(trim(...))
    ->add(StringProcessor::upper(...))
    ->add(fn($s) => "!!! $s !!!");

echo "Pipelined: " . $pipeline->process("  hello world  ") . "\n";

// 数组方法引用
$arr = ['  a  ', '  b  ', '  c  '];
$trimmed = array_map(trim(...), $arr);
echo "Trimmed: ['" . implode("', '", $trimmed) . "']\n";

// 与array_filter结合
$nums = [1, 2, 3, 4, 5, 6, 7, 8, 9, 10];
$isEven = fn($n) => $n % 2 === 0;
$evens = array_filter($nums, $isEven);
echo "Evens: " . implode(', ', array_values($evens)) . "\n";

// 组合多个callable
$compose = fn(...$fns) => fn($x) => array_reduce(
    array_reverse($fns),
    fn($acc, $fn) => $fn($acc),
    $x
);

$process = $compose(
    strlen(...),
    StringProcessor::lower(...),
    trim(...)
);

echo "Composed (strlen(lower(trim('  HELLO  ')))): " . $process("  HELLO  ") . "\n";

// 延迟执行
function createLogger(string $level): callable {
    return fn(string $msg) => echo "[$level] $msg\n";
}

// 注意：这里用echo返回void，实际应该用返回值
$infoLogger = fn(string $msg) => "[INFO] $msg";
$errorLogger = fn(string $msg) => "[ERROR] $msg";

echo $infoLogger("Application started") . "\n";
echo $errorLogger("Something went wrong") . "\n";
?>