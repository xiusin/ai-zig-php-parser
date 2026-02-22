<?php
// 超级复杂的单文件测试

echo "=== Super Complex Single File Test ===\n\n";

// 1. 复杂的类层次结构
class Animal {
    protected string $name;
    protected int $age;
    
    public function __construct(string $name, int $age) {
        $this->name = $name;
        $this->age = $age;
    }
    
    public function getName(): string {
        return $this->name;
    }
    
    public function getAge(): int {
        return $this->age;
    }
    
    public function speak(): string {
        return "Some sound";
    }
}

class Dog extends Animal {
    private string $breed;
    
    public function __construct(string $name, int $age, string $breed) {
        parent::__construct($name, $age);
        $this->breed = $breed;
    }
    
    public function speak(): string {
        return "Woof!";
    }
    
    public function getBreed(): string {
        return $this->breed;
    }
}

class Cat extends Animal {
    private bool $indoor;
    
    public function __construct(string $name, int $age, bool $indoor) {
        parent::__construct($name, $age);
        $this->indoor = $indoor;
    }
    
    public function speak(): string {
        return "Meow!";
    }
    
    public function isIndoor(): bool {
        return $this->indoor;
    }
}

echo "1. Complex Inheritance Test:\n";
$dog = new Dog("Buddy", 3, "Golden Retriever");
$cat = new Cat("Whiskers", 2, true);

echo "   Dog: " . $dog->speak() . " - " . $dog->getName() . " (" . $dog->getAge() . " years)\n";
echo "   Breed: " . $dog->getBreed() . "\n";
echo "   Cat: " . $cat->speak() . " - " . $cat->getName() . " (" . $cat->getAge() . " years)\n";
echo "   Indoor: " . ($cat->isIndoor() ? "yes" : "no") . "\n\n";

// 2. 复杂的闭包链
echo "2. Complex Closure Chain Test:\n";

function createPipeline(): callable {
    $step1 = function($x) {
        return $x + 10;
    };
    
    $step2 = function($x) {
        return $x * 2;
    };
    
    $step3 = function($x) {
        return $x - 5;
    };
    
    return function($x) use ($step1, $step2, $step3) {
        return $step3($step2($step1($x)));
    };
}

$pipeline = createPipeline();
$result = $pipeline(5);
echo "   pipeline(5) = $result\n";
echo "   Expected: (5 + 10) * 2 - 5 = 25\n\n";

// 3. 复杂的数组操作链
echo "3. Complex Array Chain Test:\n";

$data = [1, 2, 3, 4, 5, 6, 7, 8, 9, 10];

$result = array_reduce(
    array_map(
        function($x) { return $x * 2; },
        array_filter($data, function($x) { return $x % 2 === 0; })
    ),
    function($carry, $x) { return $carry + $x; },
    0
);

echo "   Result: $result\n";
echo "   Expected: (2+4+6+8+10)*2 = 60\n\n";

// 4. 复杂的递归 - 斐波那契和阶乘组合
echo "4. Complex Recursion Test:\n";

function fibonacci(int $n): int {
    if ($n <= 1) return $n;
    return fibonacci($n - 1) + fibonacci($n - 2);
}

function factorial(int $n): int {
    if ($n <= 1) return 1;
    return $n * factorial($n - 1);
}

function combined(int $n): int {
    return fibonacci($n) + factorial($n);
}

$fib5 = fibonacci(5);
$fact5 = factorial(5);
$comb5 = combined(5);

echo "   fibonacci(5) = $fib5\n";
echo "   factorial(5) = $fact5\n";
echo "   combined(5) = $comb5\n\n";

// 5. 复杂的字符串处理
echo "5. Complex String Processing Test:\n";

$text = "Hello World PHP AOT Compiler";
$words = explode(" ", $text);
$wordCount = count($words);

$longestWord = "";
$longestLength = 0;

foreach ($words as $word) {
    $len = strlen($word);
    if ($len > $longestLength) {
        $longestWord = $word;
        $longestLength = $len;
    }
}

echo "   Text: $text\n";
echo "   Words: $wordCount\n";
echo "   Longest: $longestWord ($longestLength chars)\n\n";

// 6. 复杂的控制流
echo "6. Complex Control Flow Test:\n";

$sum = 0;
$count = 0;

for ($i = 1; $i <= 10; $i++) {
    if ($i % 2 === 0) {
        for ($j = 1; $j <= $i; $j++) {
            if ($j % 2 === 1) {
                $sum += $j;
                $count++;
            }
        }
    }
}

echo "   Sum: $sum\n";
echo "   Count: $count\n";
echo "   Average: " . ($count > 0 ? $sum / $count : 0) . "\n\n";

// 7. 复杂的三元运算符嵌套
echo "7. Complex Ternary Test:\n";

function classify(int $n): string {
    return $n === 0 ? "zero" :
           ($n > 0 ? ($n % 2 === 0 ? "positive even" : "positive odd") :
                     ($n % 2 === 0 ? "negative even" : "negative odd"));
}

echo "   classify(0) = " . classify(0) . "\n";
echo "   classify(4) = " . classify(4) . "\n";
echo "   classify(5) = " . classify(5) . "\n";
echo "   classify(-4) = " . classify(-4) . "\n";
echo "   classify(-5) = " . classify(-5) . "\n\n";

echo "=== All Super Complex Tests Passed ===\n";
