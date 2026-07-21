<?php
// 极度混搭: Promise/Future + async/await模拟 + 并发 + 错误处理
echo "=== f090: Promise + Future + Async + Concurrent ===\n";

class Promise {
    public string $state = 'pending';
    private mixed $value = null;
    private mixed $reason = null;
    private array $thenCallbacks = [];
    private array $catchCallbacks = [];
    private array $finallyCallbacks = [];

    public function __construct(?callable $executor = null) {
        if ($executor !== null) {
            $executor(
                fn($v) => $this->resolve($v),
                fn($r) => $this->reject($r)
            );
        }
    }

    public function resolve(mixed $value): void {
        if ($this->state !== 'pending') return;
        $this->state = 'fulfilled';
        $this->value = $value;
        foreach ($this->thenCallbacks as $cb) $this->value = $cb($this->value) ?? $this->value;
        foreach ($this->finallyCallbacks as $cb) $cb();
    }

    public function reject(mixed $reason): void {
        if ($this->state !== 'pending') return;
        $this->state = 'rejected';
        $this->reason = $reason;
        foreach ($this->catchCallbacks as $cb) $cb($this->reason);
        foreach ($this->finallyCallbacks as $cb) $cb();
    }

    public function then(callable $cb): self {
        if ($this->state === 'fulfilled') { $this->value = $cb($this->value) ?? $this->value; }
        else { $this->thenCallbacks[] = $cb; }
        return $this;
    }

    public function catch(callable $cb): self {
        if ($this->state === 'rejected') $cb($this->reason);
        else { $this->catchCallbacks[] = $cb; }
        return $this;
    }

    public function finally(callable $cb): self {
        if ($this->state !== 'pending') $cb();
        else { $this->finallyCallbacks[] = $cb; }
        return $this;
    }

    public static function resolve2(mixed $value): self {
        $p = new self(); $p->resolve($value); return $p;
    }

    public static function reject2(mixed $reason): self {
        $p = new self(); $p->reject($reason); return $p;
    }

    public static function all(array $promises): self {
        $result = new self();
        $values = []; $count = count($promises); $completed = 0;
        foreach ($promises as $i => $p) {
            $p->then(function($v) use (&$values, &$completed, $count, $i, $result) {
                $values[$i] = $v;
                $completed++;
                if ($completed === $count) $result->resolve($values);
            });
            $p->catch(fn($r) => $result->reject($r));
        }
        return $result;
    }

    public static function race(array $promises): self {
        $result = new self();
        foreach ($promises as $p) {
            $p->then(fn($v) => $result->resolve($v));
            $p->catch(fn($r) => $result->reject($r));
        }
        return $result;
    }

    public static function any(array $promises): self {
        $result = new self();
        foreach ($promises as $p) {
            $p->then(fn($v) => $result->resolve($v));
        }
        return $result;
    }

    public function getValue(): mixed { return $this->value; }
    public function getReason(): mixed { return $this->reason; }
}

class AsyncExecutor {
    private array $tasks = [];

    public function async(callable $fn): Promise {
        $promise = new Promise();
        $this->tasks[] = ['fn' => $fn, 'promise' => $promise];
        return $promise;
    }

    public function run(): void {
        foreach ($this->tasks as $task) {
            try {
                $result = ($task['fn'])();
                $task['promise']->resolve($result);
            } catch (Exception $e) {
                $task['promise']->reject($e);
            }
        }
        $this->tasks = [];
    }

    public function await(Promise $promise): mixed {
        return $promise->getValue();
    }
}

// 测试
echo "--- Basic Promise ---\n";
$p = new Promise(fn($resolve, $reject) => $resolve(42));
$p->then(fn($v) => $v + 1)
  ->then(fn($v) => print("  Chained: $v\n"));

echo "\n--- Async/Await Simulation ---\n";
$executor = new AsyncExecutor();

$p1 = $executor->async(fn() => 10 + 20);
$p2 = $executor->async(fn() => 5 * 6);
$p3 = $executor->async(fn() => strtoupper('hello'));

$executor->run();

echo "p1 result: " . $executor->await($p1) . "\n";
echo "p2 result: " . $executor->await($p2) . "\n";
echo "p3 result: " . $executor->await($p3) . "\n";

echo "\n--- Promise.all ---\n";
$promises = [
    Promise::resolve2(1),
    Promise::resolve2(2),
    Promise::resolve2(3),
];
$all = Promise::all($promises);
echo "all result: " . json_encode($all->getValue()) . "\n";

echo "\n--- Promise.race ---\n";
$race = Promise::race([
    Promise::resolve2('first'),
    Promise::resolve2('second'),
]);
echo "race result: " . $race->getValue() . "\n";

echo "\n--- Error Handling ---\n";
$p4 = new Promise(fn($resolve, $reject) => $reject(new RuntimeException("Something failed")));
$p4->then(fn($v) => print("  Should not print: $v\n"))
   ->catch(fn($e) => print("  Caught: " . $e->getMessage() . "\n"))
   ->finally(fn() => print("  Finally called\n"));

echo "\n--- Chained Async ---\n";
$p5 = Promise::resolve2(5)
    ->then(fn($v) => $v * 2)
    ->then(fn($v) => $v + 10)
    ->then(fn($v) => $v - 3);
echo "Chain (5*2+10-3): " . $p5->getValue() . "\n";

echo "\n--- Concurrent Fetch Simulation ---\n";
$executor2 = new AsyncExecutor();
$urls = ['api/users', 'api/posts', 'api/comments', 'api/likes'];
$fetchPromises = [];
foreach ($urls as $url) {
    $fetchPromises[] = $executor2->async(function() use ($url) {
        $data = "response from $url";
        return $data;
    });
}
$executor2->run();

$results = array_map(fn($p) => $executor2->await($p), $fetchPromises);
echo "Concurrent results:\n";
foreach ($results as $r) echo "  $r\n";

echo "\n--- Aggregate with Promise.all ---\n";
$allData = Promise::all($fetchPromises);
echo "All data: " . json_encode($allData->getValue()) . "\n";

echo "=== f090 Done ===\n";
