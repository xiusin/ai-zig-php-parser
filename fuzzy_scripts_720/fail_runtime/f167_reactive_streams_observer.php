<?php
// 响应式流：观察者模式、操作符链、收集
echo "=== f167: Reactive Streams + Observer + Operators ===\n";

interface Observer {
    public function onNext(mixed $value): void;
    public function onError(Throwable $error): void;
    public function onComplete(): void;
}

class Observable {
    private $source;
    private function __construct(callable $source) { $this->source = $source; }

    public static function fromArray(array $items): self {
        return new self(function(Observer $o) use ($items) {
            foreach ($items as $item) $o->onNext($item);
            $o->onComplete();
        });
    }

    public static function range(int $start, int $count): self {
        return new self(function(Observer $o) use ($start, $count) {
            for ($i = 0; $i < $count; $i++) $o->onNext($start + $i);
            $o->onComplete();
        });
    }

    public function map(callable $fn): self {
        $up = $this;
        return new self(function(Observer $o) use ($up, $fn) {
            $up->subscribe(new class($o, $fn) implements Observer {
                function __construct(private Observer $d, private $fn) {}
                function onNext(mixed $v): void { $this->d->onNext(($this->fn)($v)); }
                function onError(Throwable $e): void { $this->d->onError($e); }
                function onComplete(): void { $this->d->onComplete(); }
            });
        });
    }

    public function filter(callable $fn): self {
        $up = $this;
        return new self(function(Observer $o) use ($up, $fn) {
            $up->subscribe(new class($o, $fn) implements Observer {
                function __construct(private Observer $d, private $fn) {}
                function onNext(mixed $v): void { if (($this->fn)($v)) $this->d->onNext($v); }
                function onError(Throwable $e): void { $this->d->onError($e); }
                function onComplete(): void { $this->d->onComplete(); }
            });
        });
    }

    public function take(int $n): self {
        $up = $this;
        return new self(function(Observer $o) use ($up, $n) {
            $c = 0;
            $up->subscribe(new class($o, $n, $c) implements Observer {
                private Observer $d; private int $lim; private int $c = 0;
                function __construct(Observer $d, int $lim) { $this->d = $d; $this->lim = $lim; }
                function onNext(mixed $v): void {
                    if ($this->c < $this->lim) { $this->d->onNext($v); $this->c++; if ($this->c >= $this->lim) $this->d->onComplete(); }
                }
                function onError(Throwable $e): void { $this->d->onError($e); }
                function onComplete(): void { $this->d->onComplete(); }
            });
        });
    }

    public function reduce(callable $fn, mixed $init = null): self {
        $up = $this;
        return new self(function(Observer $o) use ($up, $fn, $init) {
            $acc = $init;
            $up->subscribe(new class($o, $fn, $acc) implements Observer {
                private Observer $d; private $fn; private mixed $acc;
                function __construct(Observer $d, $fn, mixed &$acc) { $this->d = $d; $this->fn = $fn; $this->acc = &$acc; }
                function onNext(mixed $v): void { $this->acc = $this->acc === null ? $v : ($this->fn)($this->acc, $v); }
                function onError(Throwable $e): void { $this->d->onError($e); }
                function onComplete(): void { $this->d->onNext($this->acc); $this->d->onComplete(); }
            });
        });
    }

    public function scan(callable $fn, mixed $init): self {
        $up = $this;
        return new self(function(Observer $o) use ($up, $fn, $init) {
            $acc = $init;
            $up->subscribe(new class($o, $fn, $acc) implements Observer {
                private Observer $d; private $fn; private mixed $acc;
                function __construct(Observer $d, $fn, mixed &$acc) { $this->d = $d; $this->fn = $fn; $this->acc = &$acc; }
                function onNext(mixed $v): void { $this->acc = ($this->fn)($this->acc, $v); $this->d->onNext($this->acc); }
                function onError(Throwable $e): void { $this->d->onError($e); }
                function onComplete(): void { $this->d->onComplete(); }
            });
        });
    }

    public function subscribe(Observer $o): void { ($this->source)($o); }

    public function collect(): array {
        $vals = [];
        $this->subscribe(new class($vals) implements Observer {
            public array $v;
            function __construct(array &$v) { $this->v = &$v; }
            function onNext(mixed $val): void { $this->v[] = $val; }
            function onError(Throwable $e): void {}
            function onComplete(): void {}
        });
        return $vals;
    }
}

// 测试
echo "--- Basic Observable ---\n";
echo "  fromArray: " . implode(', ', Observable::fromArray([1,2,3,4,5])->collect()) . "\n";
echo "  range(10,5): " . implode(', ', Observable::range(10,5)->collect()) . "\n";

echo "\n--- Map & Filter ---\n";
echo "  Squares: " . implode(', ', Observable::range(1,5)->map(fn($x)=>$x*$x)->collect()) . "\n";
echo "  Evens: " . implode(', ', Observable::range(1,20)->filter(fn($x)=>$x%2===0)->collect()) . "\n";

echo "\n--- Chained ---\n";
echo "  Even squares (first 5): " . implode(', ', Observable::range(1,20)->filter(fn($x)=>$x%2===0)->map(fn($x)=>$x*$x)->take(5)->collect()) . "\n";

echo "\n--- Reduce ---\n";
$sum = Observable::range(1,10)->reduce(fn($a,$b)=>$a+$b, 0)->collect()[0];
echo "  Sum 1-10: $sum\n";
$product = Observable::range(1,5)->reduce(fn($a,$b)=>$a*$b, 1)->collect()[0];
echo "  Product 1-5: $product\n";

echo "\n--- Scan (Running Total) ---\n";
echo "  Running sum: " . implode(', ', Observable::range(1,5)->scan(fn($a,$b)=>$a+$b, 0)->collect()) . "\n";

echo "\n--- String Processing ---\n";
$words = Observable::fromArray(['hello','world','foo','bar','baz'])
    ->map(fn($s)=>strtoupper($s))
    ->filter(fn($s)=>strlen($s)>3)
    ->collect();
echo "  Long upper: " . implode(', ', $words) . "\n";

echo "=== f167 Done ===\n";
