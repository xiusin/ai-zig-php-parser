<?php
// 极度混搭: 测试框架 + 断言 + Mock + 数据提供 + 覆盖率
echo "=== f084: Test Framework + Assert + Mock + Coverage ===\n";

class TestFramework {
    private array $tests = [];
    private array $results = [];
    private array $coverage = [];
    private int $passed = 0;
    private int $failed = 0;
    private int $skipped = 0;

    public function test(string $name, callable $fn): void {
        $this->tests[] = ['name' => $name, 'fn' => $fn, 'type' => 'test'];
    }

    public function testWithDataProvider(string $name, callable $fn, array $data): void {
        foreach ($data as $i => $row) {
            $this->tests[] = ['name' => "$name #$i", 'fn' => fn() => $fn(...$row), 'type' => 'test'];
        }
    }

    public function skip(string $name): void {
        $this->tests[] = ['name' => $name, 'fn' => null, 'type' => 'skip'];
    }

    public function run(): array {
        $this->results = [];
        $this->passed = 0; $this->failed = 0; $this->skipped = 0;
        foreach ($this->tests as $test) {
            if ($test['type'] === 'skip') {
                $this->results[] = ['name' => $test['name'], 'status' => 'SKIP'];
                $this->skipped++;
                continue;
            }
            try {
                ($test['fn'])();
                $this->results[] = ['name' => $test['name'], 'status' => 'PASS'];
                $this->passed++;
            } catch (AssertionError $e) {
                $this->results[] = ['name' => $test['name'], 'status' => 'FAIL', 'message' => $e->getMessage()];
                $this->failed++;
            } catch (Exception $e) {
                $this->results[] = ['name' => $test['name'], 'status' => 'ERROR', 'message' => $e->getMessage()];
                $this->failed++;
            }
        }
        return $this->results;
    }

    public function assertEquals(mixed $expected, mixed $actual, string $msg = ''): void {
        if ($expected != $actual) throw new AssertionError($msg ?: "Expected " . json_encode($expected) . ", got " . json_encode($actual));
    }
    public function assertSame(mixed $expected, mixed $actual, string $msg = ''): void {
        if ($expected !== $actual) throw new AssertionError($msg ?: "Expected same: " . json_encode($expected) . " !== " . json_encode($actual));
    }
    public function assertTrue(mixed $val, string $msg = ''): void { if ($val !== true) throw new AssertionError($msg ?: "Expected true, got " . json_encode($val)); }
    public function assertFalse(mixed $val, string $msg = ''): void { if ($val !== false) throw new AssertionError($msg ?: "Expected false, got " . json_encode($val)); }
    public function assertNull(mixed $val, string $msg = ''): void { if ($val !== null) throw new AssertionError($msg ?: "Expected null, got " . json_encode($val)); }
    public function assertNotNull(mixed $val, string $msg = ''): void { if ($val === null) throw new AssertionError($msg ?: "Expected not null"); }
    public function assertGreaterThan(mixed $a, mixed $b, string $msg = ''): void { if (!($a > $b)) throw new AssertionError($msg ?: "Expected $a > $b"); }
    public function assertContains(string $needle, string $haystack, string $msg = ''): void { if (!str_contains($haystack, $needle)) throw new AssertionError($msg ?: "'$needle' not in '$haystack'"); }
    public function assertCount(int $expected, array $actual, string $msg = ''): void { if (count($actual) !== $expected) throw new AssertionError($msg ?: "Expected count $expected, got " . count($actual)); }

    public function trackCoverage(string $module): void {
        if (!isset($this->coverage[$module])) $this->coverage[$module] = ['called' => 0];
        $this->coverage[$module]['called']++;
    }

    public function getSummary(): array {
        return [
            'total' => count($this->results),
            'passed' => $this->passed,
            'failed' => $this->failed,
            'skipped' => $this->skipped,
            'pass_rate' => count($this->results) > 0 ? round($this->passed / count($this->results) * 100, 1) : 0,
        ];
    }
    public function getResults(): array { return $this->results; }
    public function getCoverage(): array { return $this->coverage; }
}

class Mock {
    private array $expectations = [];
    private array $calls = [];

    public function expects(string $method): MockMethod {
        if (!isset($this->expectations[$method])) $this->expectations[$method] = [];
        $m = new MockMethod($method);
        $this->expectations[$method][] = $m;
        return $m;
    }

    public function __call(string $name, array $args): mixed {
        $this->calls[] = ['method' => $name, 'args' => $args];
        if (isset($this->expectations[$name])) {
            foreach ($this->expectations[$name] as $exp) {
                if (!$exp->isMatched()) {
                    $exp->match();
                    return $exp->getReturn();
                }
            }
        }
        return null;
    }

    public function getCalls(): array { return $this->calls; }
    public function verify(): bool {
        foreach ($this->expectations as $method => $exps) {
            foreach ($exps as $exp) {
                if (!$exp->isMatched()) return false;
            }
        }
        return true;
    }
}

class MockMethod {
    private mixed $returnValue = null;
    private bool $matched = false;
    private int $expectedCalls = 1;
    private int $actualCalls = 0;

    public function __construct(private string $method) {}
    public function willReturn(mixed $value): self { $this->returnValue = $value; return $this; }
    public function withArgs(int $count): self { $this->expectedCalls = $count; return $this; }
    public function match(): void { $this->matched = true; $this->actualCalls++; }
    public function isMatched(): bool { return $this->actualCalls >= $this->expectedCalls; }
    public function getReturn(): mixed { return $this->returnValue; }
}

// 测试
$tf = new TestFramework();

// 基本测试
$tf->test('addition', function() use ($tf) {
    $tf->assertEquals(4, 2 + 2);
    $tf->assertEquals(0, 5 - 5);
    $tf->assertTrue(10 > 5);
});

$tf->test('string operations', function() use ($tf) {
    $tf->assertEquals('HELLO', strtoupper('hello'));
    $tf->assertContains('world', 'hello world');
    $tf->assertCount(3, explode(' ', 'a b c'));
});

$tf->test('array operations', function() use ($tf) {
    $arr = [1, 2, 3, 4, 5];
    $tf->assertCount(5, $arr);
    $tf->assertEquals(15, array_sum($arr));
    $tf->assertEquals(3, count(array_filter($arr, fn($x) => $x > 2)));
});

$tf->test('null and type checks', function() use ($tf) {
    $tf->assertNull(null);
    $tf->assertNotNull(0);
    $tf->assertFalse(empty([1]));
    $tf->assertTrue(is_array([]));
});

$tf->test('exception thrown', function() use ($tf) {
    try {
        throw new RuntimeException("Test exception");
        $tf->assertTrue(false, "Should have thrown");
    } catch (RuntimeException $e) {
        $tf->assertEquals("Test exception", $e->getMessage());
    }
});

// 数据提供
$tf->testWithDataProvider('factorial',
    function($n, $expected) use ($tf) {
        $fact = 1;
        for ($i = 2; $i <= $n; $i++) $fact *= $i;
        $tf->assertEquals($expected, $fact);
    },
    [
        [0, 1], [1, 1], [2, 2], [3, 6], [4, 24], [5, 120], [6, 720],
    ]
);

$tf->testWithDataProvider('string reverse',
    function($input, $expected) use ($tf) {
        $tf->assertEquals($expected, strrev($input));
    },
    [
        ['abc', 'cba'], ['hello', 'olleh'], ['', ''], ['a', 'a'], ['12345', '54321'],
    ]
);

// 跳过的测试
$tf->skip('not implemented yet');

// 失败的测试
$tf->test('deliberate failure', function() use ($tf) {
    $tf->assertEquals(1, 2, "This test is designed to fail");
});

// 运行
$results = $tf->run();

echo "--- Test Results ---\n";
foreach ($results as $r) {
    $icon = match($r['status']) { 'PASS' => '✓', 'FAIL' => '✗', 'SKIP' => '-', 'ERROR' => '!' };
    echo "  $icon {$r['name']}";
    if (isset($r['message'])) echo " — {$r['message']}";
    echo "\n";
}

echo "\n--- Summary ---\n";
$summary = $tf->getSummary();
echo "  Total: {$summary['total']}\n";
echo "  Passed: {$summary['passed']}\n";
echo "  Failed: {$summary['failed']}\n";
echo "  Skipped: {$summary['skipped']}\n";
echo "  Pass rate: {$summary['pass_rate']}%\n";

echo "\n--- Mock Test ---\n";
$mock = new Mock();
$mock->expects('getData')->willReturn(['status' => 'ok']);
$mock->expects('save')->willReturn(true);

$result = $mock->getData();
echo "getData(): " . json_encode($result) . "\n";
$saved = $mock->save(['name' => 'test']);
echo "save(): " . var_export($saved, true) . "\n";
echo "Mock verified: " . var_export($mock->verify(), true) . "\n";
echo "Mock calls: " . count($mock->getCalls()) . "\n";

echo "=== f084 Done ===\n";
