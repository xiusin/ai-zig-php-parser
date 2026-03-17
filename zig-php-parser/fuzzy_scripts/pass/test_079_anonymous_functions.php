<?php
// 测试79: 匿名函数（闭包）的高级用法
$greet = function(string $name): string {
    return "Hello, $name!";
};

echo $greet("World") . "
";

// 使用use捕获变量
$prefix = "Mr.";
$suffix = "Jr.";
$formatName = function(string $name) use ($prefix, $suffix): string {
    return "$prefix $name $suffix";
};
echo $formatName("Smith") . "
";

// 引用捕获
$counter = 0;
$increment = function() use (&$counter): int {
    return ++$counter;
};
echo "Counter: " . $increment() . " " . $increment() . " " . $increment() . "
";

// 作为回调
$numbers = [1, 2, 3, 4, 5];
$squares = array_map(function($n) { return $n * $n; }, $numbers);
echo "Squares: " . implode(", ", $squares) . "
";

// 闭包作为属性
class EventEmitter {
    private array $listeners = [];
    
    public function on(string $event, callable $listener): void {
        $this->listeners[$event][] = $listener;
    }
    
    public function emit(string $event, ...$args): void {
        foreach ($this->listeners[$event] ?? [] as $listener) {
            $listener(...$args);
        }
    }
}

$emitter = new EventEmitter();
$emitter->on('greet', function($name) {
    echo "Hello, $name!
";
});
$emitter->on('greet', function($name) {
    echo "Welcome, $name!
";
});
$emitter->emit('greet', 'Alice');

// 递归闭包
$factorial = function($n) use (&$factorial): int {
    return $n <= 1 ? 1 : $n * $factorial($n - 1);
};
echo "Factorial 5: " . $factorial(5) . "
";

// 闭包绑定
class Counter {
    private int $count = 0;
    
    public function getIncrementor(): Closure {
        return function(): int {
            return ++$this->count;
        };
    }
}

$counter = new Counter();
$inc = $counter->getIncrementor();
echo "Count: " . $inc() . " " . $inc() . " " . $inc() . "
";
?>