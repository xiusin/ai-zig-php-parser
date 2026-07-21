<?php
// Promise/Async 模拟：链式调用、并行、错误处理、延迟
echo "=== f165: Promise/Async + Chain + Parallel ===\n";

class Promise {
    private mixed $value = null;
    private ?Throwable $error = null;
    private string $state = 'pending'; // pending, fulfilled, rejected
    private array $onFulfilled = [];
    private array $onRejected = [];

    public function __construct(?callable $executor = null) {
        if ($executor !== null) {
            $executor(
                fn($v) => $this->resolve($v),
                fn($e) => $this->reject($e instanceof Throwable ? $e : new Exception((string)$e))
            );
        }
    }

    public function resolve(mixed $value): void {
        if ($this->state !== 'pending') return;
        if ($value instanceof self) {
            $value->then(fn($v) => $this->resolve($v), fn($e) => $this->reject($e));
            return;
        }
        $this->state = 'fulfilled';
        $this->value = $value;
        foreach ($this->onFulfilled as $callback) {
            $callback($value);
        }
    }

    public function reject(Throwable $error): void {
        if ($this->state !== 'pending') return;
        $this->state = 'rejected';
        $this->error = $error;
        foreach ($this->onRejected as $callback) {
            $callback($error);
        }
    }

    public function then(?callable $onFulfilled = null, ?callable $onRejected = null): self {
        $next = new self();

        $wrappedFulfill = function($value) use ($onFulfilled, $next) {
            if ($onFulfilled === null) {
                $next->resolve($value);
                return;
            }
            try {
                $result = $onFulfilled($value);
                $next->resolve($result);
            } catch (Throwable $e) {
                $next->reject($e);
            }
        };

        $wrappedReject = function(Throwable $error) use ($onRejected, $next) {
            if ($onRejected === null) {
                $next->reject($error);
                return;
            }
            try {
                $result = $onRejected($error);
                $next->resolve($result);
            } catch (Throwable $e) {
                $next->reject($e);
            }
        };

        if ($this->state === 'fulfilled') {
            $wrappedFulfill($this->value);
        } elseif ($this->state === 'rejected') {
            $wrappedReject($this->error);
        } else {
            $this->onFulfilled[] = $wrappedFulfill;
            $this->onRejected[] = $wrappedReject;
        }

        return $next;
    }

    public function catch(callable $onRejected): self {
        return $this->then(null, $onRejected);
    }

    public function finally(callable $onFinally): self {
        return $this->then(
            function($v) use ($onFinally) { $onFinally(); return $v; },
            function($e) use ($onFinally) { $onFinally(); throw $e; }
        );
    }

    public static function resolve2(mixed $value): self {
        $p = new self();
        $p->resolve($value);
        return $p;
    }

    public static function reject2(Throwable $error): self {
        $p = new self();
        $p->reject($error);
        return $p;
    }

    public static function all(array $promises): self {
        $results = [];
        $count = count($promises);
        if ($count === 0) return self::resolve2([]);
        $resolved = 0;
        $result = new self();

        foreach ($promises as $i => $promise) {
            $promise->then(
                function($v) use ($i, &$results, &$resolved, $count, $result) {
                    $results[$i] = $v;
                    $resolved++;
                    if ($resolved === $count) {
                        ksort($results);
                        $result->resolve($results);
                    }
                },
                fn($e) => $result->reject($e)
            );
        }
        return $result;
    }

    public static function race(array $promises): self {
        $result = new self();
        foreach ($promises as $promise) {
            $promise->then(fn($v) => $result->resolve($v), fn($e) => $result->reject($e));
        }
        return $result;
    }

    public function getState(): string { return $this->state; }
    public function getValue(): mixed { return $this->value; }
    public function getError(): ?Throwable { return $this->error; }
}

// 测试
echo "--- Basic Promise Chain ---\n";
Promise::resolve2(5)
    ->then(fn($x) => $x + 10)
    ->then(fn($x) => $x * 2)
    ->then(fn($x) => "Result: $x")
    ->then(function($msg) {
        echo "  $msg\n";
    });

echo "\n--- Error Handling ---\n";
Promise::resolve2(10)
    ->then(fn($x) => throw new Exception("Error at step $x"))
    ->then(fn($x) => "Should not reach here")
    ->catch(function(Throwable $e) {
        echo "  Caught: " . $e->getMessage() . "\n";
        return 'recovered';
    })
    ->then(function($v) {
        echo "  After catch: $v\n";
    });

echo "\n--- Finally ---\n";
Promise::resolve2(42)
    ->then(fn($x) => "Value: $x")
    ->finally(function() {
        echo "  [Cleanup done]\n";
    })
    ->then(function($v) {
        echo "  $v\n";
    });

echo "\n--- Promise.all ---\n";
$p1 = Promise::resolve2('A');
$p2 = Promise::resolve2('B');
$p3 = Promise::resolve2('C');

Promise::all([$p1, $p2, $p3])->then(function($results) {
    echo "  All resolved: " . implode(', ', $results) . "\n";
});

echo "\n--- Promise.all with mixed ---\n";
$pa = Promise::resolve2(1);
$pb = Promise::resolve2(2);
$pc = new Promise();
$pc->resolve(3);

Promise::all([$pa, $pb, $pc])->then(function($results) {
    echo "  Sum: " . array_sum($results) . "\n";
    echo "  Values: " . implode(', ', $results) . "\n";
});

echo "\n--- Promise.race ---\n";
$fast = Promise::resolve2('fast');
$slow = new Promise();
Promise::race([$fast, $slow])->then(function($v) {
    echo "  Winner: $v\n";
});

echo "\n--- Chained Async Simulation ---\n";
function fetchUser(int $id): Promise {
    return Promise::resolve2(['id' => $id, 'name' => "User$id", 'email' => "user$id@example.com"]);
}

function fetchPosts(int $userId): Promise {
    return Promise::resolve2([
        ['id' => 1, 'title' => 'Post 1', 'userId' => $userId],
        ['id' => 2, 'title' => 'Post 2', 'userId' => $userId],
    ]);
}

function fetchComments(int $postId): Promise {
    return Promise::resolve2([
        ['id' => 101, 'postId' => $postId, 'text' => 'Great!'],
        ['id' => 102, 'postId' => $postId, 'text' => 'Nice'],
    ]);
}

fetchUser(42)
    ->then(function($user) {
        echo "  User: {$user['name']}\n";
        return fetchPosts($user['id']);
    })
    ->then(function($posts) {
        echo "  Posts: " . count($posts) . "\n";
        foreach ($posts as $post) {
            echo "    - {$post['title']}\n";
        }
        return fetchComments($posts[0]['id']);
    })
    ->then(function($comments) {
        echo "  Comments for first post:\n";
        foreach ($comments as $comment) {
            echo "    - {$comment['text']}\n";
        }
    })
    ->catch(function(Throwable $e) {
        echo "  Error: " . $e->getMessage() . "\n";
    });

echo "\n--- Parallel Execution ---\n";
$tasks = [
    Promise::resolve2('Task A result'),
    Promise::resolve2('Task B result'),
    Promise::resolve2('Task C result'),
];

Promise::all($tasks)->then(function($results) {
    foreach ($results as $i => $result) {
        echo "  Task $i: $result\n";
    }
});

echo "=== f165 Done ===\n";
