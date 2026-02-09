<?php
/**
 * AOT 高级特性测试
 * 测试：类、继承、接口、闭包、高阶函数等
 */

echo "=== 基础类测试 ===\n";

class Person {
    private $name;
    private $age;
    
    public function __construct($name, $age) {
        $this->name = $name;
        $this->age = $age;
    }
    
    public function getName() {
        return $this->name;
    }
    
    public function getAge() {
        return $this->age;
    }
    
    public function greet() {
        return "Hello, I'm " . $this->name;
    }
}

$person = new Person("Alice", 30);
echo $person->greet() . "\n";
echo "Age: " . $person->getAge() . "\n";

echo "\n=== 继承测试 ===\n";

class Employee extends Person {
    private $salary;
    
    public function __construct($name, $age, $salary) {
        parent::__construct($name, $age);
        $this->salary = $salary;
    }
    
    public function getSalary() {
        return $this->salary;
    }
    
    public function greet() {
        return parent::greet() . " and I work here";
    }
}

$emp = new Employee("Bob", 25, 50000);
echo $emp->greet() . "\n";
echo "Salary: " . $emp->getSalary() . "\n";

echo "\n=== 闭包测试 ===\n";

$multiplier = 3;
$multiply = function($x) use ($multiplier) {
    return $x * $multiplier;
};

echo "5 * 3 = " . $multiply(5) . "\n";

// 闭包作为参数
function applyOperation($value, $operation) {
    return $operation($value);
}

$result = applyOperation(10, function($x) {
    return $x * 2;
});
echo "10 * 2 = " . $result . "\n";

echo "\n=== 高阶函数测试 ===\n";

function map($array, $callback) {
    $result = [];
    foreach ($array as $item) {
        $result[] = $callback($item);
    }
    return $result;
}

function filter($array, $callback) {
    $result = [];
    foreach ($array as $item) {
        if ($callback($item)) {
            $result[] = $item;
        }
    }
    return $result;
}

$numbers = [1, 2, 3, 4, 5];
$squared = map($numbers, function($x) { return $x * $x; });
echo "Squared: " . implode(", ", $squared) . "\n";

$evens = filter($numbers, function($x) { return $x % 2 == 0; });
echo "Evens: " . implode(", ", $evens) . "\n";

echo "\n=== 静态方法测试 ===\n";

class Math {
    public static function add($a, $b) {
        return $a + $b;
    }
    
    public static function multiply($a, $b) {
        return $a * $b;
    }
}

echo "Math::add(5, 3) = " . Math::add(5, 3) . "\n";
echo "Math::multiply(4, 7) = " . Math::multiply(4, 7) . "\n";

echo "\n=== 递归函数测试 ===\n";

function factorial($n) {
    if ($n <= 1) {
        return 1;
    }
    return $n * factorial($n - 1);
}

echo "factorial(5) = " . factorial(5) . "\n";
echo "factorial(10) = " . factorial(10) . "\n";

function fibonacci($n) {
    if ($n <= 1) {
        return $n;
    }
    return fibonacci($n - 1) + fibonacci($n - 2);
}

echo "fibonacci(10) = " . fibonacci(10) . "\n";

echo "\n=== 数组方法测试 ===\n";

class ArrayList {
    private $items = [];
    
    public function add($item) {
        $this->items[] = $item;
    }
    
    public function get($index) {
        return $this->items[$index];
    }
    
    public function size() {
        return count($this->items);
    }
    
    public function map($callback) {
        $result = new ArrayList();
        foreach ($this->items as $item) {
            $result->add($callback($item));
        }
        return $result;
    }
}

$list = new ArrayList();
$list->add(1);
$list->add(2);
$list->add(3);

echo "List size: " . $list->size() . "\n";
echo "First item: " . $list->get(0) . "\n";

$doubled = $list->map(function($x) { return $x * 2; });
echo "Doubled first: " . $doubled->get(0) . "\n";

echo "\n=== 链式调用测试 ===\n";

class Calculator {
    private $value = 0;
    
    public function add($n) {
        $this->value += $n;
        return $this;
    }
    
    public function multiply($n) {
        $this->value *= $n;
        return $this;
    }
    
    public function subtract($n) {
        $this->value -= $n;
        return $this;
    }
    
    public function getValue() {
        return $this->value;
    }
}

$calc = new Calculator();
$result = $calc->add(10)->multiply(2)->subtract(5)->getValue();
echo "Chain result: " . $result . "\n";

echo "\n=== 匿名类测试 ===\n";

function createCounter($start) {
    return new class($start) {
        private $count;
        
        public function __construct($initial) {
            $this->count = $initial;
        }
        
        public function increment() {
            $this->count++;
            return $this->count;
        }
        
        public function getCount() {
            return $this->count;
        }
    };
}

$counter = createCounter(5);
echo "Initial: " . $counter->getCount() . "\n";
echo "After increment: " . $counter->increment() . "\n";
echo "After increment: " . $counter->increment() . "\n";

echo "\n=== 复杂闭包测试 ===\n";

function makeAdder($x) {
    return function($y) use ($x) {
        return $x + $y;
    };
}

$add5 = makeAdder(5);
$add10 = makeAdder(10);

echo "add5(3) = " . $add5(3) . "\n";
echo "add10(3) = " . $add10(3) . "\n";

echo "\n=== 嵌套闭包测试 ===\n";

function outer($x) {
    return function($y) use ($x) {
        return function($z) use ($x, $y) {
            return $x + $y + $z;
        };
    };
}

$f = outer(1);
$g = $f(2);
echo "outer(1)(2)(3) = " . $g(3) . "\n";

echo "\n=== 所有测试完成 ===\n";
