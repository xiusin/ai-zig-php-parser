<?php
// 极度混搭: 测试框架 + 断言 + Mock + 数据提供 + 覆盖率
echo "=== f130: Test Framework + Assert + Mock + Coverage ===\n";

class TestResult {
    public array $assertions = [];
    public int $passed = 0;
    public int $failed = 0;
    public float $duration = 0;

    public function __construct(public string $name) {}

    public function addAssertion(string $name, bool $passed, string $message = ''): void {
        $this->assertions[] = ['name' => $name, 'passed' => $passed, 'message' => $message];
        if ($passed) $this->passed++; else $this->failed++;
    }
}

class TestCase {
    protected TestResult $result;
    public array $setUp = [];
    public array $tearDown = [];

    public function run(): TestResult {
        $this->result = new TestResult(static::class);
        $start = microtime(true);
        $methods = get_class_methods($this);
        foreach ($methods as $method) {
            if (!str_starts_with($method, 'test')) continue;
            $this->setUp();
            try {
                $this->$method();
            } catch (Exception $e) {
                $this->result->addAssertion($method, false, $e->getMessage());
            }
            $this->tearDown();
        }
        $this->result->duration = microtime(true) - $start;
        return $this->result;
    }

    protected function setUp(): void { foreach ($this->setUp as $fn) $fn(); }
    protected function tearDown(): void { foreach ($this->tearDown as $fn) $fn(); }

    protected function assertTrue($value, string $message = ''): void { $this->result->addAssertion(debug_backtrace()[1]['function'], (bool)$value, $message ?: 'assertTrue failed'); }
    protected function assertFalse($value, string $message = ''): void { $this->result->addAssertion(debug_backtrace()[1]['function'], !$value, $message ?: 'assertFalse failed'); }
    protected function assertEquals($expected, $actual, string $message = ''): void { $this->result->addAssertion(debug_backtrace()[1]['function'], $expected === $actual, $message ?: "Expected " . var_export($expected, true) . " got " . var_export($actual, true)); }
    protected function assertNotEquals($expected, $actual, string $message = ''): void { $this->result->addAssertion(debug_backtrace()[1]['function'], $expected !== $actual, $message); }
    protected function assertGreaterThan($expected, $actual, string $message = ''): void { $this->result->addAssertion(debug_backtrace()[1]['function'], $actual > $expected, $message); }
    protected function assertContains($needle, array $haystack, string $message = ''): void { $this->result->addAssertion(debug_backtrace()[1]['function'], in_array($needle, $haystack), $message); }
    protected function assertCount(int $expected, array $actual, string $message = ''): void { $this->result->addAssertion(debug_backtrace()[1]['function'], count($actual) === $expected, $message); }
}

class Mock {
    private array $expectations = [];
    private array $calls = [];
    private array $returnValues = [];

    public function __construct(private string $className) {}

    public function expects(string $method): MockMethod {
        if (!isset($this->expectations[$method])) $this->expectations[$method] = new MockMethod($method);
        return $this->expectations[$method];
    }

    public function __call(string $method, array $args) {
        $this->calls[] = ['method' => $method, 'args' => $args];
        if (isset($this->returnValues[$method])) {
            $callback = $this->returnValues[$method];
            return $callback($args);
        }
        return null;
    }

    public function getCalls(string $method = ''): array {
        if ($method === '') return $this->calls;
        return array_filter($this->calls, fn($c) => $c['method'] === $method);
    }

    public function verify(): array {
        $results = [];
        foreach ($this->expectations as $method => $exp) {
            $calls = $this->getCalls($method);
            $results[$method] = ['expected' => $exp->callCount, 'actual' => count($calls), 'pass' => count($calls) >= $exp->callCount];
        }
        return $results;
    }
}

class MockMethod {
    public int $callCount = 1;
    public function __construct(public string $method) {}
    public function times(int $n): self { $this->callCount = $n; return $this; }
    public function once(): self { $this->callCount = 1; return $this; }
    public function never(): self { $this->callCount = 0; return $this; }
    public function willReturn($value): void {}
}

class CoverageTracker {
    private array $covered = [];
    private array $total = [];

    public function register(string $class, array $methods): void {
        $this->total[$class] = $methods;
        $this->covered[$class] = array_fill_keys($methods, 0);
    }

    public function markCovered(string $class, string $method): void {
        if (isset($this->covered[$class][$method])) $this->covered[$class][$method]++;
    }

    public function getCoverage(): array {
        $result = [];
        foreach ($this->total as $class => $methods) {
            $covered = count(array_filter($this->covered[$class], fn($c) => $c > 0));
            $result[$class] = ['total' => count($methods), 'covered' => $covered, 'percent' => count($methods) > 0 ? $covered / count($methods) * 100 : 0];
        }
        return $result;
    }

    public function getOverallPercent(): float {
        $totalMethods = array_sum(array_map('count', $this->total));
        $coveredMethods = 0;
        foreach ($this->covered as $class => $methods) {
            $coveredMethods += count(array_filter($methods, fn($c) => $c > 0));
        }
        return $totalMethods > 0 ? $coveredMethods / $totalMethods * 100 : 0;
    }
}

class TestRunner {
    private array $results = [];
    private CoverageTracker $coverage;

    public function __construct() { $this->coverage = new CoverageTracker(); }

    public function addTest(TestCase $test): void { $this->results[] = $test->run(); }
    public function getCoverageTracker(): CoverageTracker { return $this->coverage; }

    public function runAll(): array {
        $totalPassed = 0; $totalFailed = 0;
        foreach ($this->results as $result) {
            $totalPassed += $result->passed;
            $totalFailed += $result->failed;
        }
        return ['tests' => count($this->results), 'passed' => $totalPassed, 'failed' => $totalFailed, 'pass_rate' => $totalPassed + $totalFailed > 0 ? $totalPassed / ($totalPassed + $totalFailed) * 100 : 0];
    }

    public function report(): string {
        $stats = $this->runAll();
        $output = "=== Test Report ===\n";
        $output .= "Tests: {$stats['tests']}, Passed: {$stats['passed']}, Failed: {$stats['failed']}\n";
        $output .= "Pass rate: " . number_format($stats['pass_rate'], 1) . "%\n\n";
        foreach ($this->results as $result) {
            $status = $result->failed === 0 ? 'PASS' : 'FAIL';
            $output .= "[$status] {$result->name} ({$result->passed}/" . ($result->passed + $result->failed) . ", " . number_format($result->duration * 1000, 1) . "ms)\n";
            if ($result->failed > 0) {
                foreach ($result->assertions as $a) {
                    if (!$a['passed']) $output .= "  ✗ {$a['name']}: {$a['message']}\n";
                }
            }
        }
        $coverage = $this->coverage->getCoverage();
        if (!empty($coverage)) {
            $output .= "\n--- Coverage ---\n";
            foreach ($coverage as $class => $c) {
                $output .= "  $class: {$c['covered']}/{$c['total']} (" . number_format($c['percent'], 0) . "%)\n";
            }
            $output .= "  Overall: " . number_format($this->coverage->getOverallPercent(), 1) . "%\n";
        }
        return $output;
    }
}

// 测试: 被测代码
class Calculator {
    public function add($a, $b) { return $a + $b; }
    public function subtract($a, $b) { return $a - $b; }
    public function multiply($a, $b) { return $a * $b; }
    public function divide($a, $b) {
        if ($b === 0) throw new Exception('Division by zero');
        return $a / $b;
    }
}

class Stack {
    private array $items = [];
    public function push($item): void { $this->items[] = $item; }
    public function pop() { return array_pop($this->items); }
    public function peek() { return end($this->items) ?: null; }
    public function size(): int { return count($this->items); }
    public function isEmpty(): bool { return empty($this->items); }
}

// 测试用例
class CalculatorTest extends TestCase {
    private Calculator $calc;
    protected function setUp(): void { $this->calc = new Calculator(); }

    public function testAdd() {
        $this->assertEquals(5, $this->calc->add(2, 3));
        $this->assertEquals(-1, $this->calc->add(2, -3));
        $this->assertEquals(0, $this->calc->add(0, 0));
    }
    public function testSubtract() {
        $this->assertEquals(-1, $this->calc->subtract(2, 3));
        $this->assertEquals(5, $this->calc->subtract(10, 5));
    }
    public function testMultiply() {
        $this->assertEquals(6, $this->calc->multiply(2, 3));
        $this->assertEquals(0, $this->calc->multiply(5, 0));
    }
    public function testDivide() {
        $this->assertEquals(2.5, $this->calc->divide(5, 2));
        $this->assertEquals(3, $this->calc->divide(9, 3));
    }
    public function testDivideByZero() {
        try { $this->calc->divide(1, 0); $this->assertTrue(false, 'Should throw'); }
        catch (Exception $e) { $this->assertTrue(true); }
    }
}

class StackTest extends TestCase {
    private Stack $stack;
    protected function setUp(): void { $this->stack = new Stack(); }

    public function testPushAndPop() {
        $this->stack->push('a');
        $this->stack->push('b');
        $this->assertEquals(2, $this->stack->size());
        $this->assertEquals('b', $this->stack->pop());
        $this->assertEquals(1, $this->stack->size());
    }
    public function testPeek() {
        $this->stack->push('x');
        $this->assertEquals('x', $this->stack->peek());
        $this->assertEquals(1, $this->stack->size());
    }
    public function testEmpty() {
        $this->assertTrue($this->stack->isEmpty());
        $this->stack->push('x');
        $this->assertFalse($this->stack->isEmpty());
    }
    public function testPopEmpty() {
        $this->assertNull($this->stack->pop());
    }
}

// 运行测试
echo "--- Run Test Suite ---\n";
$runner = new TestRunner();
$runner->getCoverageTracker()->register('Calculator', ['add', 'subtract', 'multiply', 'divide']);
$runner->getCoverageTracker()->register('Stack', ['push', 'pop', 'peek', 'size', 'isEmpty']);
$runner->getCoverageTracker()->markCovered('Calculator', 'add');
$runner->getCoverageTracker()->markCovered('Calculator', 'subtract');
$runner->getCoverageTracker()->markCovered('Calculator', 'multiply');
$runner->getCoverageTracker()->markCovered('Calculator', 'divide');
$runner->getCoverageTracker()->markCovered('Stack', 'push');
$runner->getCoverageTracker()->markCovered('Stack', 'pop');
$runner->getCoverageTracker()->markCovered('Stack', 'peek');
$runner->getCoverageTracker()->markCovered('Stack', 'size');
$runner->getCoverageTracker()->markCovered('Stack', 'isEmpty');

$runner->addTest(new CalculatorTest());
$runner->addTest(new StackTest());

echo $runner->report();

echo "\n--- Mock Test ---\n";
$mockDb = new Mock('Database');
$mockDb->expects('query')->once();
$mockDb->expects('fetch')->times(2);
$mockDb->__call('query', ['SELECT * FROM users']);
$mockDb->__call('fetch', []);
$mockDb->__call('fetch', []);
$verify = $mockDb->verify();
echo "Mock verification:\n";
foreach ($verify as $method => $v) {
    $status = $v['pass'] ? '✓' : '✗';
    echo "  $status $method: expected={$v['expected']} actual={$v['actual']}\n";
}

echo "\n--- Data Provider Example ---\n";
$dataProvider = [
    [1, 2, 3], [10, 20, 30], [-5, 5, 0], [100, 200, 300],
];
$calc = new Calculator();
foreach ($dataProvider as [$a, $b, $expected]) {
    $result = $calc->add($a, $b);
    $status = $result === $expected ? '✓' : '✗';
    echo "  $status add($a, $b) = $result (expected $expected)\n";
}

echo "=== f130 Done ===\n";
