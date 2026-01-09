<?php
/**
 * 高级随机PHP测试用例生成器
 * 用于生成复杂功能的测试用例：OOP、闭包、内存管理、错误处理等
 */

class AdvancedPHPTestGenerator {
    private $outputDir;
    
    public function __construct($outputDir = './examples') {
        $this->outputDir = $outputDir;
        if (!is_dir($this->outputDir)) {
            mkdir($this->outputDir, 0755, true);
        }
    }
    
    /**
     * 生成OOP高级测试
     */
    public function generateAdvancedOOPTests() {
        $tests = [
            // 多重继承模拟测试
            '<?php
trait CanEat {
    public function eat($food) {
        return "Eating " . $food;
    }
}

trait CanSleep {
    public function sleep($hours) {
        return "Sleeping for " . $hours . " hours";
    }
}

trait CanWork {
    public function work($task) {
        return "Working on " . $task;
    }
}

class Human {
    use CanEat, CanSleep, CanWork;
    private $name;
    private $age;
    
    public function __construct($name, $age) {
        $this->name = $name;
        $this->age = $age;
    }
    
    public function getInfo() {
        return $this->name . " is " . $this->age . " years old";
    }
}

$human = new Human("Alice", 30);
echo $human->getInfo() . "\n";
echo $human->eat("apple") . "\n";
echo $human->sleep(8) . "\n";
echo $human->work("project") . "\n";
?>',
            
            // 接口和多态测试
            '<?php
interface Shape {
    public function area();
    public function perimeter();
}

class Circle implements Shape {
    private $radius;
    
    public function __construct($radius) {
        $this->radius = $radius;
    }
    
    public function area() {
        return pi() * $this->radius * $this->radius;
    }
    
    public function perimeter() {
        return 2 * pi() * $this->radius;
    }
}

class Rectangle implements Shape {
    private $width;
    private $height;
    
    public function __construct($width, $height) {
        $this->width = $width;
        $this->height = $height;
    }
    
    public function area() {
        return $this->width * $this->height;
    }
    
    public function perimeter() {
        return 2 * ($this->width + $this->height);
    }
}

function printShapeInfo(Shape $shape) {
    echo "Area: " . $shape->area() . "\n";
    echo "Perimeter: " . $shape->perimeter() . "\n";
}

$circle = new Circle(5);
$rectangle = new Rectangle(4, 6);

printShapeInfo($circle);
printShapeInfo($rectangle);
?>',
            
            // 抽象类和继承测试
            '<?php
abstract class Animal {
    protected $name;
    
    public function __construct($name) {
        $this->name = $name;
    }
    
    abstract public function speak();
    abstract public function move();
    
    public function getName() {
        return $this->name;
    }
}

class Dog extends Animal {
    public function speak() {
        return "Woof!";
    }
    
    public function move() {
        return "Running";
    }
}

class Cat extends Animal {
    public function speak() {
        return "Meow!";
    }
    
    public function move() {
        return "Walking";
    }
}

$dog = new Dog("Buddy");
$cat = new Cat("Whiskers");

echo $dog->getName() . " says: " . $dog->speak() . "\n";
echo $dog->getName() . " is: " . $dog->move() . "\n";
echo $cat->getName() . " says: " . $cat->speak() . "\n";
echo $cat->getName() . " is: " . $cat->move() . "\n";
?>',
            
            // 静态方法和属性测试
            '<?php
class Counter {
    private static $count = 0;
    private $id;
    
    public function __construct() {
        self::$count = self::$count + 1;
        $this->id = self::$count;
    }
    
    public static function getCount() {
        return self::$count;
    }
    
    public function getId() {
        return $this->id;
    }
    
    public function __destruct() {
        self::$count = self::$count - 1;
    }
}

echo "Initial count: " . Counter::getCount() . "\n";

$counter1 = new Counter();
echo "After counter1: " . Counter::getCount() . "\n";

$counter2 = new Counter();
echo "After counter2: " . Counter::getCount() . "\n";

$counter3 = new Counter();
echo "After counter3: " . Counter::getCount() . "\n";

echo "Counter1 ID: " . $counter1->getId() . "\n";
echo "Counter2 ID: " . $counter2->getId() . "\n";
echo "Counter3 ID: " . $counter3->getId() . "\n";
?>',
            
            // 魔术方法测试
            '<?php
class MagicClass {
    private $data = array();
    
    public function __set($name, $value) {
        $this->data[$name] = $value;
        echo "Setting " . $name . " to " . $value . "\n";
    }
    
    public function __get($name) {
        if (array_key_exists($name, $this->data)) {
            return $this->data[$name];
        }
        return "Property " . $name . " not found";
    }
    
    public function __call($name, $arguments) {
        echo "Calling method " . $name . " with arguments: " . implode(", ", $arguments) . "\n";
        return "Method result";
    }
    
    public static function __callStatic($name, $arguments) {
        echo "Calling static method " . $name . "\n";
        return "Static method result";
    }
    
    public function __toString() {
        return "MagicClass instance";
    }
    
    public function __isset($name) {
        return isset($this->data[$name]);
    }
    
    public function __unset($name) {
        unset($this->data[$name]);
        echo "Unsetting " . $name . "\n";
    }
}

$obj = new MagicClass();
$obj->property1 = "value1";
$obj->property2 = "value2";

echo "property1: " . $obj->property1 . "\n";
echo "property2: " . $obj->property2 . "\n";
echo "undefined: " . $obj->undefined . "\n";

$obj->someMethod(1, 2, 3);
MagicClass::staticMethod();

echo "String representation: " . $obj . "\n";
echo "Isset property1: " . (isset($obj->property1) ? "Yes" : "No") . "\n";

unset($obj->property1);
echo "Isset property1 after unset: " . (isset($obj->property1) ? "Yes" : "No") . "\n";
?>'
        ];
        
        foreach ($tests as $i => $test) {
            $filename = $this->outputDir . "/test_oop_advanced_" . $i . ".php";
            file_put_contents($filename, $test);
            echo "Generated: " . $filename . "\n";
        }
    }
    
    /**
     * 生成闭包和箭头函数测试
     */
    public function generateClosureTests() {
        $tests = [
            '<?php
function createCounter($start, $step) {
    $count = $start;
    return function() use (&$count, $step) {
        $count = $count + $step;
        return $count;
    };
}

$counter1 = createCounter(0, 1);
$counter2 = createCounter(10, 2);

echo "Counter1: " . $counter1() . "\n";
echo "Counter1: " . $counter1() . "\n";
echo "Counter1: " . $counter1() . "\n";

echo "Counter2: " . $counter2() . "\n";
echo "Counter2: " . $counter2() . "\n";
echo "Counter2: " . $counter2() . "\n";
?>',
            
            '<?php
$factorial = function($n) use (&$factorial) {
    if ($n <= 1) {
        return 1;
    }
    return $n * $factorial($n - 1);
};

echo "Factorial of 5: " . $factorial(5) . "\n";
echo "Factorial of 10: " . $factorial(10) . "\n";

$fibonacci = function($n) use (&$fibonacci) {
    if ($n <= 1) {
        return $n;
    }
    return $fibonacci($n - 1) + $fibonacci($n - 2);
};

echo "Fibonacci of 10: " . $fibonacci(10) . "\n";
echo "Fibonacci of 15: " . $fibonacci(15) . "\n";
?>',
            
            '<?php
$numbers = array(1, 2, 3, 4, 5, 6, 7, 8, 9, 10);

// 过滤偶数
$even = array_filter($numbers, function($x) { return $x % 2 == 0; });
echo "Even numbers: " . implode(", ", $even) . "\n";

// 平方
$squared = array_map(function($x) { return $x * $x; }, $numbers);
echo "Squared: " . implode(", ", $squared) . "\n";

// 求和
$sum = array_reduce($numbers, function($carry, $item) { return $carry + $item; }, 0);
echo "Sum: " . $sum . "\n";

// 创建加法器
function createAdder($base) {
    return function($x) use ($base) { return $base + $x; };
}

$add5 = createAdder(5);
$add10 = createAdder(10);

echo "5 + 3 = " . $add5(3) . "\n";
echo "10 + 7 = " . $add10(7) . "\n";
echo "5 + 100 = " . $add5(100) . "\n";
?>',
            
            '<?php
class EventManager {
    private $handlers = array();
    
    public function on($event, $handler) {
        $this->handlers[$event] = $handler;
    }
    
    public function trigger($event, $data) {
        if (isset($this->handlers[$event])) {
            return $this->handlers[$event]($data);
        }
        return null;
    }
}

$events = new EventManager();

$events->on("user.created", function($user) {
    return "User created: " . $user["name"];
});

$events->on("user.updated", function($user) {
    return "User updated: " . $user["name"];
});

echo $events->trigger("user.created", array("name" => "Alice")) . "\n";
echo $events->trigger("user.updated", array("name" => "Bob")) . "\n";
?>'
        ];
        
        foreach ($tests as $i => $test) {
            $filename = $this->outputDir . "/test_closure_" . $i . ".php";
            file_put_contents($filename, $test);
            echo "Generated: " . $filename . "\n";
        }
    }
    
    /**
     * 生成数组高级测试
     */
    public function generateAdvancedArrayTests() {
        $tests = [
            '<?php
$matrix = array(
    array(1, 2, 3),
    array(4, 5, 6),
    array(7, 8, 9)
);

echo "Matrix:\n";
foreach ($matrix as $row) {
    echo implode(" ", $row) . "\n";
}

// 数组转换
$doubled = array_map(function($arr) {
    return array_map(function($x) { return $x * 2; }, $arr);
}, $matrix);

echo "\nDoubled:\n";
foreach ($doubled as $row) {
    echo implode(" ", $row) . "\n";
}

// 深度数组操作
$deep = array(
    "a" => array(1, 2, 3),
    "b" => array(4, 5, 6),
    "c" => array(7, 8, 9)
);

$processed = array_map(function($arr) {
    return array(
        "sum" => array_sum($arr),
        "count" => count($arr),
        "avg" => array_sum($arr) / count($arr)
    );
}, $deep);

echo "\nProcessed:\n";
print_r($processed);
?>',
            
            '<?php
$original = array(1, 2, 3, 4, 5);
$reference = &$original;
$copy = $original;

echo "Original: " . implode(", ", $original) . "\n";
echo "Reference: " . implode(", ", $reference) . "\n";
echo "Copy: " . implode(", ", $copy) . "\n";

$reference[0] = 100;
echo "\nAfter modifying reference[0] to 100:\n";
echo "Original: " . implode(", ", $original) . "\n";
echo "Reference: " . implode(", ", $reference) . "\n";
echo "Copy: " . implode(", ", $copy) . "\n";
?>',
            
            '<?php
$data = array(
    array("name" => "Alice", "age" => 30, "city" => "New York"),
    array("name" => "Bob", "age" => 25, "city" => "Los Angeles"),
    array("name" => "Charlie", "age" => 35, "city" => "New York"),
    array("name" => "Diana", "age" => 28, "city" => "Chicago")
);

// 按年龄排序
usort($data, function($a, $b) { return $a["age"] - $b["age"]; });
echo "Sorted by age:\n";
print_r($data);

// 按城市分组
$grouped = array();
foreach ($data as $person) {
    $city = $person["city"];
    if (!isset($grouped[$city])) {
        $grouped[$city] = array();
    }
    $grouped[$city][] = $person;
}
echo "\nGrouped by city:\n";
print_r($grouped);

// 提取名称
$names = array_column($data, "name");
echo "\nNames: " . implode(", ", $names) . "\n";
?>'
        ];
        
        foreach ($tests as $i => $test) {
            $filename = $this->outputDir . "/test_array_advanced_" . $i . ".php";
            file_put_contents($filename, $test);
            echo "Generated: " . $filename . "\n";
        }
    }
    
    /**
     * 生成错误处理测试
     */
    public function generateErrorHandlingTests() {
        $tests = [
            '<?php
class CustomException extends Exception {}
class ValidationException extends Exception {}

function validate($value) {
    if ($value === null) {
        throw new ValidationException("Value cannot be null");
    }
    if ($value === "") {
        throw new CustomException("Value cannot be empty");
    }
    return true;
}

try {
    validate(null);
} catch (ValidationException $e) {
    echo "Caught ValidationException: " . $e->getMessage() . "\n";
} catch (CustomException $e) {
    echo "Caught CustomException: " . $e->getMessage() . "\n";
} catch (Exception $e) {
    echo "Caught Exception: " . $e->getMessage() . "\n";
}

try {
    validate("");
} catch (ValidationException $e) {
    echo "Caught ValidationException: " . $e->getMessage() . "\n";
} catch (CustomException $e) {
    echo "Caught CustomException: " . $e->getMessage() . "\n";
} catch (Exception $e) {
    echo "Caught Exception: " . $e->getMessage() . "\n";
}

try {
    validate("valid");
    echo "Validation passed\n";
} catch (Exception $e) {
    echo "Caught Exception: " . $e->getMessage() . "\n";
}
?>',
            
            '<?php
function handleErrors($e) {
    echo "Caught: " . get_class($e) . "\n";
    echo "Message: " . $e->getMessage() . "\n";
    echo "File: " . $e->getFile() . "\n";
    echo "Line: " . $e->getLine() . "\n";
}

try {
    throw new Error("This is an Error");
} catch (Throwable $e) {
    handleErrors($e);
}

echo "\n";

try {
    throw new Exception("This is an Exception");
} catch (Throwable $e) {
    handleErrors($e);
}
?>',
            
            '<?php
function testFinally($shouldThrow) {
    echo "Starting testFinally\n";
    try {
        echo "In try block\n";
        if ($shouldThrow) {
            throw new Exception("Thrown from try");
        }
        return "Return from try";
    } catch (Exception $e) {
        echo "In catch block: " . $e->getMessage() . "\n";
        return "Return from catch";
    } finally {
        echo "In finally block\n";
    }
    echo "This should never be printed\n";
}

echo "Test 1 (no throw):\n";
echo testFinally(false) . "\n";

echo "\nTest 2 (with throw):\n";
echo testFinally(true) . "\n";
?>'
        ];
        
        foreach ($tests as $i => $test) {
            $filename = $this->outputDir . "/test_error_handling_advanced_" . $i . ".php";
            file_put_contents($filename, $test);
            echo "Generated: " . $filename . "\n";
        }
    }
    
    /**
     * 生成并发模拟测试
     */
    public function generateConcurrencyTests() {
        $tests = [
            '<?php
function simulateTask($name, $duration) {
    echo $name . " started (duration: " . $duration . "s)\n";
    $start = time();
    while ((time() - $start) < $duration) {
        // 模拟工作
    }
    echo $name . " completed\n";
    return $name . " result";
}

echo "=== Sequential execution ===\n";
$result1 = simulateTask("Task1", 1);
$result2 = simulateTask("Task2", 1);
echo "Results: " . $result1 . ", " . $result2 . "\n";
?>',
            
            '<?php
class SharedCounter {
    private $value = 0;
    private $name;
    
    public function __construct($name) {
        $this->name = $name;
    }
    
    public function increment() {
        $this->value = $this->value + 1;
    }
    
    public function getValue() {
        return $this->value;
    }
    
    public function getName() {
        return $this->name;
    }
}

$counter = new SharedCounter("Counter");

for ($i = 0; $i < 5; $i++) {
    $counter->increment();
    echo $counter->getName() . " value after increment " . $i . ": " . $counter->getValue() . "\n";
}

echo "Final " . $counter->getName() . " value: " . $counter->getValue() . "\n";
?>',
            
            '<?php
class Channel {
    private $queue = array();
    
    public function send($value) {
        $this->queue[] = $value;
    }
    
    public function receive() {
        return array_shift($this->queue);
    }
    
    public function isEmpty() {
        return empty($this->queue);
    }
}

$channel = new Channel();

$channel->send("message1");
$channel->send("message2");
$channel->send("message3");

while (!$channel->isEmpty()) {
    echo "Received: " . $channel->receive() . "\n";
}
?>'
        ];
        
        foreach ($tests as $i => $test) {
            $filename = $this->outputDir . "/test_concurrency_simulated_" . $i . ".php";
            file_put_contents($filename, $test);
            echo "Generated: " . $filename . "\n";
        }
    }
    
    /**
     * 生成内存管理测试
     */
    public function generateMemoryTests() {
        $tests = [
            '<?php
class RefCounted {
    public $data;
    
    public function __construct($data) {
        $this->data = $data;
    }
    
    public function __destruct() {
        echo "Destroying RefCounted with data: " . $this->data . "\n";
    }
}

echo "Creating object\n";
$obj1 = new RefCounted("data1");
$obj2 = $obj1;
$obj3 = $obj1;

echo "Copying to obj2 and obj3\n";
echo "After copy, obj1 refcount should be 3\n";

unset($obj1);
echo "After unset obj1\n";

unset($obj2);
echo "After unset obj2\n";

unset($obj3);
echo "After unset obj3 (should trigger destructor)\n";
?>',
            
            '<?php
class Node {
    public $value;
    public $next;
    
    public function __construct($value) {
        $this->value = $value;
    }
    
    public function __destruct() {
        echo "Destroying node: " . $this->value . "\n";
    }
}

$node1 = new Node("1");
$node2 = new Node("2");
$node3 = new Node("3");

$node1->next = $node2;
$node2->next = $node3;
$node3->next = $node1;

echo "Created circular linked list\n";

unset($node1);
echo "After unset node1\n";

unset($node2);
echo "After unset node2\n";

unset($node3);
echo "After unset node3\n";
?>',
            
            '<?php
function createLargeArray($size) {
    $arr = array();
    for ($i = 0; $i < $size; $i++) {
        $arr[] = array(
            "id" => $i,
            "value" => "value_" . $i,
            "data" => str_repeat("x", 100)
        );
    }
    return $arr;
}

echo "Creating large array (10000 elements)\n";
$largeArray = createLargeArray(10000);
echo "Array created, count: " . count($largeArray) . "\n";

echo "First element ID: " . $largeArray[0]["id"] . "\n";
echo "Last element ID: " . $largeArray[count($largeArray) - 1]["id"] . "\n";

echo "Clearing array\n";
unset($largeArray);
echo "Array cleared\n";
?>'
        ];
        
        foreach ($tests as $i => $test) {
            $filename = $this->outputDir . "/test_memory_" . $i . ".php";
            file_put_contents($filename, $test);
            echo "Generated: " . $filename . "\n";
        }
    }
    
    /**
     * 生成所有高级测试
     */
    public function generateAllAdvancedTests() {
        echo "Generating advanced OOP tests...\n";
        $this->generateAdvancedOOPTests();
        
        echo "Generating closure tests...\n";
        $this->generateClosureTests();
        
        echo "Generating advanced array tests...\n";
        $this->generateAdvancedArrayTests();
        
        echo "Generating error handling tests...\n";
        $this->generateErrorHandlingTests();
        
        echo "Generating concurrency tests...\n";
        $this->generateConcurrencyTests();
        
        echo "Generating memory tests...\n";
        $this->generateMemoryTests();
        
        echo "\n=== All advanced tests generated successfully! ===\n";
    }
}

// 如果直接运行此脚本
if (basename(__FILE__) === basename($_SERVER["SCRIPT_FILENAME"])) {
    $generator = new AdvancedPHPTestGenerator();
    $generator->generateAllAdvancedTests();
}
?>
