<?php
// Closures and closure binding
class Counter {
    private $count = 0;
    
    public function increment() {
        $this->count++;
    }
    
    public function getCount() {
        return $this->count;
    }
    
    public function getIncrementer() {
        return function() {
            $this->increment();
        };
    }
    
    public function getGetter() {
        return function() {
            return $this->getCount();
        };
    }
}

class Calculator {
    private $result = 0;
    
    public function add($num) {
        $this->result += $num;
        return $this;
    }
    
    public function subtract($num) {
        $this->result -= $num;
        return $this;
    }
    
    public function multiply($num) {
        $this->result *= $num;
        return $this;
    }
    
    public function getResult() {
        return $this->result;
    }
    
    public function reset() {
        $this->result = 0;
        return $this;
    }
    
    public function getOperation($op) {
        return match($op) {
            'add' => fn($num) => $this->add($num),
            'subtract' => fn($num) => $this->subtract($num),
            'multiply' => fn($num) => $this->multiply($num),
            'result' => fn() => $this->getResult(),
            'reset' => fn() => $this->reset(),
            default => throw new InvalidArgumentException("Unknown operation"),
        };
    }
}

class EventDispatcher {
    private $listeners = [];
    
    public function on($event, callable $listener) {
        if (!isset($this->listeners[$event])) {
            $this->listeners[$event] = [];
        }
        $this->listeners[$event][] = $listener;
    }
    
    public function dispatch($event, $data = null) {
        if (!isset($this->listeners[$event])) {
            return;
        }
        
        foreach ($this->listeners[$event] as $listener) {
            $listener($data);
        }
    }
    
    public function off($event, callable $listener = null) {
        if ($listener === null) {
            unset($this->listeners[$event]);
        } else {
            $key = array_search($listener, $this->listeners[$event], true);
            if ($key !== false) {
                unset($this->listeners[$event][$key]);
            }
        }
    }
}

class Pipeline {
    private $stages = [];
    
    public function pipe(callable $stage) {
        $this->stages[] = $stage;
        return $this;
    }
    
    public function process($data) {
        foreach ($this->stages as $stage) {
            $data = $stage($data);
        }
        return $data;
    }
    
    public function reset() {
        $this->stages = [];
        return $this;
    }
}

// Test closures
echo "=== Counter Testing ===\n";
$counter = new Counter();

$incrementer = $counter->getIncrementer();
$getter = $counter->getGetter();

echo "Initial count: {$counter->getCount()}\n";

$incrementer();
echo "After increment: {$counter->getCount()}\n";

$incrementer();
$incrementer();
echo "After 2 more increments: {$counter->getCount()}\n";

echo "Via getter: {$getter()}\n";

echo "\n=== Calculator Testing ===\n";
$calc = new Calculator();

$add = $calc->getOperation('add');
$subtract = $calc->getOperation('subtract');
$multiply = $calc->getOperation('multiply');
$result = $calc->getOperation('result');
$reset = $calc->getOperation('reset');

$add(10);
echo "After add(10): {$result()}\n";

$subtract(3);
echo "After subtract(3): {$result()}\n";

$multiply(2);
echo "After multiply(2): {$result()}\n";

$reset();
echo "After reset: {$result()}\n";

echo "\n=== Event Dispatcher Testing ===\n";
$dispatcher = new EventDispatcher();

$dispatcher->on('user.created', function($data) {
    echo "User created: {$data['name']}\n";
});

$dispatcher->on('user.created', function($data) {
    echo "Sending welcome email to {$data['email']}\n";
});

$dispatcher->on('user.deleted', function($data) {
    echo "User deleted: {$data['name']}\n";
});

echo "Dispatching user.created:\n";
$dispatcher->dispatch('user.created', ['name' => 'John', 'email' => 'john@example.com']);

echo "\nDispatching user.deleted:\n";
$dispatcher->dispatch('user.deleted', ['name' => 'Jane']);

echo "\n=== Pipeline Testing ===\n";
$pipeline = new Pipeline();

$pipeline->pipe(fn($text) => trim($text))
        ->pipe(fn($text) => strtoupper($text))
        ->pipe(fn($text) => str_replace(' ', '_', $text));

$input = "  hello world  ";
$output = $pipeline->process($input);

echo "Input: '{$input}'\n";
echo "Output: '{$output}'\n";

$pipeline->reset();
$pipeline->pipe(fn($num) => $num * 2)
        ->pipe(fn($num) => $num + 10)
        ->pipe(fn($num) => $num / 2);

$number = 5;
$result = $pipeline->process($number);
echo "Pipeline result for {$number}: {$result}\n";

echo "\n=== Closure Scoping Testing ===\n";
function createMultiplier($factor) {
    return function($number) use ($factor) {
        return $number * $factor;
    };
}

$doubler = createMultiplier(2);
$tripler = createMultiplier(3);

echo "Double 5: {$doubler(5)}\n";
echo "Triple 5: {$tripler(5)}\n";

function createAccumulator() {
    $sum = 0;
    return function($value = null) use (&$sum) {
        if ($value === null) {
            return $sum;
        }
        $sum += $value;
        return $sum;
    };
}

$accumulator = createAccumulator();
echo "Accumulate 10: {$accumulator(10)}\n";
echo "Accumulate 20: {$accumulator(20)}\n";
echo "Accumulate 30: {$accumulator(30)}\n";
echo "Current sum: {$accumulator()}\n";

echo "\nDone\n";
