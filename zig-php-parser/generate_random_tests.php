#!/usr/bin/env php
<?php
/**
 * 随机PHP测试用例生成器
 * 用于生成各种PHP功能的测试用例，以发现潜在问题
 */

class PHPTestGenerator {
    private $outputDir;
    private $testCounter = 0;
    
    public function __construct($outputDir = './examples') {
        $this->outputDir = $outputDir;
        if (!is_dir($this->outputDir)) {
            mkdir($this->outputDir, 0755, true);
        }
    }
    
    /**
     * 生成基础语法测试
     */
    public function generateBasicSyntaxTests() {
        $tests = [
            '<?php
// 变量声明和赋值
$var1 = 10;
$var2 = "hello";
$var3 = true;
$var4 = null;
echo "Variables: $var1, $var2, $var3, " . var_export($var4, true) . "\\n";
?>',
            
            '<?php
// 常量定义
define("CONSTANT", "value");
const ANOTHER_CONSTANT = 42;
echo CONSTANT . "\\n";
echo ANOTHER_CONSTANT . "\\n";
?>',
            
            '<?php
// 字面量测试
$int = 123;
$float = 123.45;
$string = "test string";
$bool = true;
echo "$int, $float, $string, $bool\\n";
?>'
        ];
        
        foreach ($tests as $i => $test) {
            $filename = $this->outputDir . "/test_basic_" . $i . ".php";
            file_put_contents($filename, $test);
            echo "Generated: $filename\n";
        }
    }
    
    /**
     * 生成流程控制测试
     */
    public function generateControlFlowTests() {
        $tests = [
            '<?php
// if/else 测试
$a = 10;
if ($a > 5) {
    echo "a is greater than 5\\n";
} else {
    echo "a is not greater than 5\\n";
}

// switch 测试
$color = "red";
switch ($color) {
    case "red":
        echo "Color is red\\n";
        break;
    case "blue":
        echo "Color is blue\\n";
        break;
    default:
        echo "Color is something else\\n";
}
?>',
            
            '<?php
// while 循环测试
$i = 0;
while ($i < 5) {
    echo "i = $i\\n";
    $i++;
}

// for 循环测试
for ($j = 0; $j < 3; $j++) {
    echo "j = $j\\n";
}

// foreach 测试
$array = [1, 2, 3];
foreach ($array as $value) {
    echo "value = $value\\n";
}
?>',
            
            '<?php
// try/catch 测试
try {
    $result = 10 / 0;
} catch (DivisionByZeroError $e) {
    echo "Caught division by zero: " . $e->getMessage() . "\\n";
} catch (Exception $e) {
    echo "Caught exception: " . $e->getMessage() . "\\n";
} finally {
    echo "Finally block executed\\n";
}
?>'
        ];
        
        foreach ($tests as $i => $test) {
            $filename = $this->outputDir . "/test_control_flow_" . $i . ".php";
            file_put_contents($filename, $test);
            echo "Generated: $filename\n";
        }
    }
    
    /**
     * 生成函数系统测试
     */
    public function generateFunctionTests() {
        $tests = [
            '<?php
// 普通函数测试
function greet($name) {
    return "Hello, " . $name;
}

echo greet("World") . "\\n";

// 可变参数函数测试
function sum(...$numbers) {
    return array_sum($numbers);
}

echo "Sum: " . sum(1, 2, 3, 4, 5) . "\\n";

// 默认参数测试
function create_user($name, $age = 18) {
    return ["name" => $name, "age" => $age];
}

$user = create_user("Alice");
print_r($user);
?>',
            
            '<?php
// 闭包测试
$multiplier = function($factor) {
    return function($number) use ($factor) {
        return $number * $factor;
    };
};

$double = $multiplier(2);
echo "Double of 5: " . $double(5) . "\\n";

// 箭头函数测试
$numbers = [1, 2, 3, 4, 5];
$squared = array_map(fn($x) => $x * $x, $numbers);
echo "Squared: " . implode(", ", $squared) . "\\n";
?>',
            
            '<?php
// 高阶函数测试
function apply_operation($array, $operation) {
    return array_map($operation, $array);
}

$numbers = [1, 2, 3, 4, 5];
$incremented = apply_operation($numbers, fn($x) => $x + 1);
echo "Incremented: " . implode(", ", $incremented) . "\\n";

// 递归函数测试
function factorial($n) {
    if ($n <= 1) {
        return 1;
    }
    return $n * factorial($n - 1);
}

echo "Factorial of 5: " . factorial(5) . "\\n";
?>'
        ];
        
        foreach ($tests as $i => $test) {
            $filename = $this->outputDir . "/test_functions_" . $i . ".php";
            file_put_contents($filename, $test);
            echo "Generated: $filename\n";
        }
    }
    
    /**
     * 生成面向对象测试
     */
    public function generateOOPTests() {
        $tests = [
            '<?php
// 类和对象测试
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
        return "Hello, I\'m " . $this->name . " and I\'m " . $this->age . " years old.";
    }
}

$person = new Person("Alice", 30);
echo $person->greet() . "\\n";
echo "Name: " . $person->getName() . "\\n";
echo "Age: " . $person->getAge() . "\\n";
?>',
            
            '<?php
// 继承测试
class Animal {
    protected $name;
    
    public function __construct($name) {
        $this->name = $name;
    }
    
    public function speak() {
        return $this->name . " makes a sound";
    }
}

class Dog extends Animal {
    public function speak() {
        return $this->name . " barks";
    }
}

$dog = new Dog("Buddy");
echo $dog->speak() . "\\n";
?>',
            
            '<?php
// 接口和 trait 测试
interface Drawable {
    public function draw();
}

trait Colorable {
    private $color;
    
    public function setColor($color) {
        $this->color = $color;
    }
    
    public function getColor() {
        return $this->color;
    }
}

class Circle implements Drawable {
    use Colorable;
    
    private $radius;
    
    public function __construct($radius) {
        $this->radius = $radius;
    }
    
    public function draw() {
        return "Drawing a circle with radius " . $this->radius;
    }
}

$circle = new Circle(5);
$circle->setColor("red");
echo $circle->draw() . "\\n";
echo "Color: " . $circle->getColor() . "\\n";
?>'
        ];
        
        foreach ($tests as $i => $test) {
            $filename = $this->outputDir . "/test_oop_" . $i . ".php";
            file_put_contents($filename, $test);
            echo "Generated: $filename\n";
        }
    }
    
    /**
     * 生成数组系统测试
     */
    public function generateArrayTests() {
        $tests = [
            '<?php
// 索引数组测试
$numbers = [1, 2, 3, 4, 5];
echo "Numbers: " . implode(", ", $numbers) . "\\n";

// 关联数组测试
$person = [
    "name" => "John Doe",
    "age" => 30,
    "city" => "New York"
];

echo "Person: " . $person["name"] . ", Age: " . $person["age"] . "\\n";

// 多维数组测试
$matrix = [
    [1, 2, 3],
    [4, 5, 6],
    [7, 8, 9]
];

echo "Matrix:\\n";
foreach ($matrix as $row) {
    echo implode(" ", $row) . "\\n";
}
?>',
            
            '<?php
// 数组函数测试
$numbers = [1, 2, 3, 4, 5];

// array_map
$doubled = array_map(function($x) { return $x * 2; }, $numbers);
echo "Doubled: " . implode(", ", $doubled) . "\\n";

// array_filter
$evens = array_filter($numbers, function($x) { return $x % 2 === 0; });
echo "Even numbers: " . implode(", ", $evens) . "\\n";

// array_reduce
$sum = array_reduce($numbers, function($carry, $item) { return $carry + $item; }, 0);
echo "Sum: $sum\\n";

// array_push/array_pop
array_push($numbers, 6, 7);
echo "After push: " . implode(", ", $numbers) . "\\n";

$last = array_pop($numbers);
echo "Popped: $last, Remaining: " . implode(", ", $numbers) . "\\n";
?>',
            
            '<?php
// 数组引用测试
$array = [1, 2, 3];
$ref = &$array[0];
$ref = 100;
echo "Array after reference modification: " . implode(", ", $array) . "\\n";

// 数组排序测试
$unsorted = [3, 1, 4, 1, 5, 9, 2, 6];
sort($unsorted);
echo "Sorted: " . implode(", ", $unsorted) . "\\n";
?>'
        ];
        
        foreach ($tests as $i => $test) {
            $filename = $this->outputDir . "/test_arrays_" . $i . ".php";
            file_put_contents($filename, $test);
            echo "Generated: $filename\n";
        }
    }
    
    /**
     * 生成并发系统测试
     */
    public function generateConcurrencyTests() {
        $tests = [
            '<?php
// 基础并发测试
echo "Starting concurrency test\\n";

// 模拟并发操作
function worker($id) {
    echo "Worker $id started\\n";
    // 模拟一些工作
    for ($i = 0; $i < 3; $i++) {
        echo "Worker $id doing work $i\\n";
        // 模拟延迟
        usleep(100000);
    }
    echo "Worker $id finished\\n";
}

// 启动多个"线程"
for ($i = 1; $i <= 3; $i++) {
    // 在实际实现中，这会是真正的并发
    worker($i);
}

echo "Concurrency test completed\\n";
?>',
            
            '<?php
// 简单的计数器并发测试
$counter = 0;

// 模拟并发增加
for ($i = 0; $i < 10; $i++) {
    $counter++;
    echo "Counter: $counter\\n";
}

echo "Final counter value: $counter\\n";
?>'
        ];
        
        foreach ($tests as $i => $test) {
            $filename = $this->outputDir . "/test_concurrency_" . $i . ".php";
            file_put_contents($filename, $test);
            echo "Generated: $filename\n";
        }
    }
    
    /**
     * 生成错误处理测试
     */
    public function generateErrorHandlingTests() {
        $tests = [
            '<?php
// 错误处理测试
function risky_function() {
    if (rand(0, 1)) {
        throw new Exception("Something went wrong");
    }
    return "Success";
}

try {
    $result = risky_function();
    echo "Result: $result\\n";
} catch (Exception $e) {
    echo "Caught exception: " . $e->getMessage() . "\\n";
} finally {
    echo "Finally block executed\\n";
}
?>',
            
            '<?php
// 未定义变量测试
echo "Testing undefined variables\\n";
// 这会生成警告而不是错误
@$undefined_var;
echo "Undefined variable test completed\\n";

// 除零错误测试
try {
    $result = 10 / 0;
} catch (DivisionByZeroError $e) {
    echo "Division by zero caught: " . $e->getMessage() . "\\n";
}
?>'
        ];
        
        foreach ($tests as $i => $test) {
            $filename = $this->outputDir . "/test_error_handling_" . $i . ".php";
            file_put_contents($filename, $test);
            echo "Generated: $filename\n";
        }
    }
    
    /**
     * 生成复杂嵌套结构测试
     */
    public function generateComplexTests() {
        $tests = [
            '<?php
// 复杂嵌套测试
class ComplexObject {
    public $data = [];
    
    public function __construct() {
        $this->data = [
            "users" => [
                ["name" => "Alice", "age" => 30],
                ["name" => "Bob", "age" => 25]
            ],
            "settings" => [
                "theme" => "dark",
                "notifications" => true
            ]
        ];
    }
    
    public function process() {
        $result = [];
        foreach ($this->data["users"] as $user) {
            $result[] = [
                "name" => strtoupper($user["name"]),
                "age_group" => $user["age"] >= 30 ? "senior" : "junior"
            ];
        }
        return $result;
    }
}

$obj = new ComplexObject();
$processed = $obj->process();
echo "Processed data: ";
print_r($processed);
?>',
            
            '<?php
// 复杂函数调用链测试
function outer($x) {
    return function($y) use ($x) {
        return function($z) use ($x, $y) {
            return $x + $y + $z;
        };
    };
}

$func = outer(10);
$func2 = $func(20);
$result = $func2(30);
echo "Nested closure result: $result\\n";

// 复杂数组操作
$matrix = [
    [1, 2, 3],
    [4, 5, 6],
    [7, 8, 9]
];

$flattened = array_merge(...$matrix);
echo "Flattened: " . implode(", ", $flattened) . "\\n";
?>'
        ];
        
        foreach ($tests as $i => $test) {
            $filename = $this->outputDir . "/test_complex_" . $i . ".php";
            file_put_contents($filename, $test);
            echo "Generated: $filename\n";
        }
    }
    
    /**
     * 生成所有测试
     */
    public function generateAllTests() {
        echo "Generating basic syntax tests...\n";
        $this->generateBasicSyntaxTests();
        
        echo "Generating control flow tests...\n";
        $this->generateControlFlowTests();
        
        echo "Generating function tests...\n";
        $this->generateFunctionTests();
        
        echo "Generating OOP tests...\n";
        $this->generateOOPTests();
        
        echo "Generating array tests...\n";
        $this->generateArrayTests();
        
        echo "Generating concurrency tests...\n";
        $this->generateConcurrencyTests();
        
        echo "Generating error handling tests...\n";
        $this->generateErrorHandlingTests();
        
        echo "Generating complex tests...\n";
        $this->generateComplexTests();
        
        echo "All tests generated successfully!\n";
    }
}

// 如果直接运行此脚本
if (basename(__FILE__) === basename($_SERVER['PHP_SELF'])) {
    $generator = new PHPTestGenerator();
    $generator->generateAllTests();
}
?>