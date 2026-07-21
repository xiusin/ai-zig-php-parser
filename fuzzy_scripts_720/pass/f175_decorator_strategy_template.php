<?php
// 装饰器+策略+模板方法：组合式行为扩展
echo "=== f175: Decorator + Strategy + Template Method ===\n";

// 装饰器：日志格式化
interface LoggerFormatter {
    public function format(string $level, string $message, array $context = []): string;
}

class BaseFormatter implements LoggerFormatter {
    public function format(string $level, string $message, array $context = []): string {
        return "[$level] $message";
    }
}

abstract class FormatterDecorator implements LoggerFormatter {
    protected LoggerFormatter $inner;
    public function __construct(LoggerFormatter $inner) { $this->inner = $inner; }
}

class TimestampDecorator extends FormatterDecorator {
    public function format(string $level, string $message, array $context = []): string {
        $ts = date('Y-m-d H:i:s');
        return "[$ts] " . $this->inner->format($level, $message, $context);
    }
}

class ContextDecorator extends FormatterDecorator {
    public function format(string $level, string $message, array $context = []): string {
        $base = $this->inner->format($level, $message, $context);
        if (empty($context)) return $base;
        return "$base " . json_encode($context);
    }
}

class ColorDecorator extends FormatterDecorator {
    private array $colors = [
        'ERROR' => "\033[31m", 'WARN' => "\033[33m", 'INFO' => "\033[32m",
        'DEBUG' => "\033[36m", 'RESET' => "\033[0m",
    ];
    public function format(string $level, string $message, array $context = []): string {
        $color = $this->colors[$level] ?? '';
        $reset = $this->colors['RESET'];
        return $color . $this->inner->format($level, $message, $context) . $reset;
    }
}

class CallerInfoDecorator extends FormatterDecorator {
    public function format(string $level, string $message, array $context = []): string {
        $caller = $context['_caller'] ?? 'unknown';
        return $this->inner->format($level, $message, $context) . " <{$caller}>";
    }
}

// 策略：排序策略
interface SortStrategy {
    public function sort(array $items): array;
    public function getName(): string;
}

class BubbleSort implements SortStrategy {
    public function sort(array $items): array {
        $n = count($items);
        for ($i = 0; $i < $n - 1; $i++) {
            for ($j = 0; $j < $n - $i - 1; $j++) {
                if ($items[$j] > $items[$j + 1]) {
                    [$items[$j], $items[$j + 1]] = [$items[$j + 1], $items[$j]];
                }
            }
        }
        return $items;
    }
    public function getName(): string { return 'BubbleSort'; }
}

class QuickSort implements SortStrategy {
    public function sort(array $items): array {
        if (count($items) <= 1) return $items;
        $pivot = $items[0];
        $left = $right = [];
        for ($i = 1; $i < count($items); $i++) {
            if ($items[$i] < $pivot) $left[] = $items[$i];
            else $right[] = $items[$i];
        }
        return array_merge($this->sort($left), [$pivot], $this->sort($right));
    }
    public function getName(): string { return 'QuickSort'; }
}

class MergeSort implements SortStrategy {
    public function sort(array $items): array {
        if (count($items) <= 1) return $items;
        $mid = (int)(count($items) / 2);
        $left = $this->sort(array_slice($items, 0, $mid));
        $right = $this->sort(array_slice($items, $mid));
        $result = [];
        $i = $j = 0;
        while ($i < count($left) && $j < count($right)) {
            if ($left[$i] <= $right[$j]) $result[] = $left[$i++];
            else $result[] = $right[$j++];
        }
        return array_merge($result, array_slice($left, $i), array_slice($right, $j));
    }
    public function getName(): string { return 'MergeSort'; }
}

class SortContext {
    private SortStrategy $strategy;
    public function __construct(SortStrategy $strategy) { $this->strategy = $strategy; }
    public function setStrategy(SortStrategy $strategy): void { $this->strategy = $strategy; }
    public function execute(array $items): array { return $this->strategy->sort($items); }
    public function getStrategyName(): string { return $this->strategy->getName(); }
}

// 模板方法：数据处理管道
abstract class DataProcessor {
    public final function process(array $data): array {
        $data = $this->validate($data);
        $data = $this->transform($data);
        $data = $this->filter($data);
        return $data;
    }

    abstract protected function validate(array $data): array;
    abstract protected function transform(array $data): array;

    protected function filter(array $data): array {
        return $data; // 默认不过滤
    }
}

class UserProcessor extends DataProcessor {
    protected function validate(array $data): array {
        return array_filter($data, fn($u) => !empty($u['name']) && !empty($u['email']));
    }

    protected function transform(array $data): array {
        return array_map(function($u) {
            $u['name'] = ucfirst(strtolower($u['name']));
            $u['email'] = strtolower($u['email']);
            $u['display'] = "{$u['name']} <{$u['email']}>";
            return $u;
        }, $data);
    }

    protected function filter(array $data): array {
        return array_filter($data, fn($u) => filter_var($u['email'], FILTER_VALIDATE_EMAIL));
    }
}

class ProductProcessor extends DataProcessor {
    protected function validate(array $data): array {
        return array_filter($data, fn($p) => isset($p['price']) && $p['price'] > 0);
    }

    protected function transform(array $data): array {
        return array_map(function($p) {
            $p['price'] = (float)$p['price'];
            $p['tax'] = $p['price'] * 0.08;
            $p['total'] = $p['price'] + $p['tax'];
            return $p;
        }, $data);
    }

    protected function filter(array $data): array {
        return array_filter($data, fn($p) => $p['price'] < 10000);
    }
}

// 测试
echo "--- Decorator: Logger Formatting ---\n";
$formatter = new BaseFormatter();
echo "  Base: " . $formatter->format('INFO', 'Hello') . "\n";

$tsFormatter = new TimestampDecorator($formatter);
echo "  +Timestamp: " . $tsFormatter->format('INFO', 'Hello') . "\n";

$ctxFormatter = new ContextDecorator($tsFormatter);
echo "  +Context: " . $ctxFormatter->format('ERROR', 'Failed', ['code' => 500, 'file' => 'app.php']) . "\n";

$callerFormatter = new CallerInfoDecorator($ctxFormatter);
echo "  +Caller: " . $callerFormatter->format('WARN', 'Slow query', ['_caller' => 'UserRepo', 'duration' => 2.5]) . "\n";

echo "\n--- Strategy: Sorting ---\n";
$data = [64, 34, 25, 12, 22, 11, 90, 1, 45, 33];
echo "  Original: " . implode(', ', $data) . "\n";

$strategies = [new BubbleSort(), new QuickSort(), new MergeSort()];
$context = new SortContext($strategies[0]);

foreach ($strategies as $strategy) {
    $context->setStrategy($strategy);
    $sorted = $context->execute($data);
    echo "  {$context->getStrategyName()}: " . implode(', ', $sorted) . "\n";
}

echo "\n--- Template Method: Data Processing ---\n";
$users = [
    ['name' => 'ALICE', 'email' => 'ALICE@test.com', 'age' => 30],
    ['name' => '', 'email' => 'bob@test.com', 'age' => 25],
    ['name' => 'CHARLIE', 'email' => 'invalid', 'age' => 35],
    ['name' => 'diana', 'email' => 'diana@test.com', 'age' => 28],
];

echo "  User processing:\n";
$processor = new UserProcessor();
$processed = $processor->process($users);
foreach ($processed as $u) {
    echo "    {$u['display']}\n";
}

$products = [
    ['name' => 'Widget', 'price' => '10.50'],
    ['name' => 'Gadget', 'price' => '0'],
    ['name' => 'Gizmo', 'price' => '25.00'],
    ['name' => 'Expensive', 'price' => '15000'],
    ['name' => 'Cheap', 'price' => '5.99'],
];

echo "\n  Product processing:\n";
$prodProcessor = new ProductProcessor();
$processedProducts = $prodProcessor->process($products);
foreach ($processedProducts as $p) {
    echo "    {$p['name']}: \${$p['price']} + \${$p['tax']} tax = \${$p['total']}\n";
}

echo "=== f175 Done ===\n";
