<?php
/**
 * 复杂PHP功能随机测试生成器
 * 覆盖：递归、对象引用、对象判断、数组操作、函数参数等
 */

$output_dir = 'examples/tests/complex/';

// 创建目录结构
$categories = [
    'recursion' => '递归测试',
    'object_reference' => '对象引用测试',
    'object_type' => '对象类型判断测试',
    'arrays' => '数组操作测试',
    'function_params' => '函数参数测试',
    'mixed' => '混合复杂功能测试',
];

foreach ($categories as $dir => $desc) {
    $full_path = $output_dir . $dir;
    if (!is_dir($full_path)) {
        mkdir($full_path, 0755, true);
    }
}

// 模板生成器

/**
 * 生成递归测试
 */
function generateRecursionTests($output_dir) {
    $tests = [];

    // 测试1：阶乘递归
    $tests[] = [
        'name' => 'test_recursion_factorial.php',
        'desc' => '递归阶乘',
        'code' => '<?php
function factorial($n) {
    if ($n <= 1) {
        return 1;
    }
    return $n * factorial($n - 1);
}

for ($i = 0; $i <= 10; $i++) {
    echo "factorial($i) = " . factorial($i) . "\n";
}
'
    ];

    // 测试2：斐波那契递归
    $tests[] = [
        'name' => 'test_recursion_fibonacci.php',
        'desc' => '递归斐波那契',
        'code' => '<?php
function fibonacci($n) {
    if ($n <= 1) {
        return $n;
    }
    return fibonacci($n - 1) + fibonacci($n - 2);
}

for ($i = 0; $i <= 15; $i++) {
    echo "fibonacci($i) = " . fibonacci($i) . "\n";
}
'
    ];

    // 测试3：递归求和
    $tests[] = [
        'name' => 'test_recursion_sum.php',
        'desc' => '递归数组求和',
        'code' => '<?php
function arraySum($arr) {
    if (empty($arr)) {
        return 0;
    }
    $first = array_shift($arr);
    if (is_array($first)) {
        return arraySum($first) + arraySum($arr);
    }
    return $first + arraySum($arr);
}

$testArrays = [
    [1, 2, 3, 4, 5],
    [10, [20, 30], 40],
    [[1, [2, [3, [4]]]]],
    range(1, 100),
];

foreach ($testArrays as $i => $arr) {
    echo "Array $i sum: " . arraySum($arr) . "\n";
}
'
    ];

    // 测试4：递归目录遍历
    $tests[] = [
        'name' => 'test_recursion_directory.php',
        'desc' => '递归目录遍历模拟',
        'code' => '<?php
function countFiles($dir, $depth = 0) {
    if ($depth > 3) {
        return 0;
    }
    $count = 0;
    // 模拟目录结构
    $items = ["file1.txt", "file2.txt"];
    if ($depth < 2) {
        $items[] = "subdir1";
        $items[] = "subdir2";
    }
    foreach ($items as $item) {
        $count++;
        if (is_dir($item) && $depth < 2) {
            $count += countFiles($item, $depth + 1);
        }
    }
    return $count;
}

echo "File count: " . countFiles(".") . "\n";
'
    ];

    // 测试5：互相递归
    $tests[] = [
        'name' => 'test_recursion_mutual.php',
        'desc' => '互相递归',
        'code' => '<?php
function isEven($n) {
    if ($n == 0) {
        return true;
    }
    return isOdd($n - 1);
}

function isOdd($n) {
    if ($n == 0) {
        return false;
    }
    return isEven($n - 1);
}

for ($i = 0; $i <= 20; $i++) {
    echo "$i is " . (isEven($i) ? "even" : "odd") . "\n";
}
'
    ];

    // 测试6：尾递归优化模拟
    $tests[] = [
        'name' => 'test_recursion_tail.php',
        'desc' => '尾递归',
        'code' => '<?php
function tailSum($n, $acc = 0) {
    if ($n <= 0) {
        return $acc;
    }
    return tailSum($n - 1, $acc + $n);
}

echo "Sum 1-100: " . tailSum(100) . "\n";
echo "Sum 1-1000: " . tailSum(1000) . "\n";
'
    ];

    // 测试7：嵌套递归
    $tests[] = [
        'name' => 'test_recursion_nested.php',
        'desc' => '嵌套递归',
        'code' => '<?php
function nested($level, $max) {
    if ($level >= $max) {
        return $level;
    }
    $sum = 0;
    for ($i = 0; $i < 3; $i++) {
        $sum += nested($level + 1, $max);
    }
    return $sum;
}

echo "Nested result: " . nested(0, 4) . "\n";
'
    ];

    // 测试8：递归深拷贝
    $tests[] = [
        'name' => 'test_recursion_deep_copy.php',
        'desc' => '递归深拷贝',
        'code' => '<?php
function deepCopy($arr) {
    if (!is_array($arr)) {
        return $arr;
    }
    $copy = [];
    foreach ($arr as $key => $value) {
        $copy[$key] = deepCopy($value);
    }
    return $copy;
}

$original = [
    "a" => 1,
    "b" => [2, 3, "c" => [4, 5]],
    "d" => [
        "e" => 6,
        "f" => [7, 8, 9]
    ]
];

$copy = deepCopy($original);
$copy["b"]["c"][0] = 999;
echo "Original: " . json_encode($original) . "\n";
echo "Copy: " . json_encode($copy) . "\n";
echo "Original unchanged: " . ($original["b"]["c"][0] == 4 ? "YES" : "NO") . "\n";
'
    ];

    // 测试9：递归对象树
    $tests[] = [
        'name' => 'test_recursion_tree.php',
        'desc' => '递归对象树',
        'code' => '<?php
class TreeNode {
    public $value;
    public $children = [];

    public function __construct($value) {
        $this->value = $value;
    }

    public function addChild($node) {
        $this->children[] = $node;
    }

    public function traverse($depth = 0) {
        echo str_repeat("  ", $depth) . $this->value . "\n";
        foreach ($this->children as $child) {
            $child->traverse($depth + 1);
        }
    }
}

$root = new TreeNode("Root");
$child1 = new TreeNode("Child1");
$child2 = new TreeNode("Child2");
$grandchild1 = new TreeNode("GrandChild1");
$grandchild2 = new TreeNode("GrandChild2");

$child1->addChild($grandchild1);
$child1->addChild($grandchild2);
$root->addChild($child1);
$root->addChild($child2);

$root->traverse();
'
    ];

    // 测试10：递归JSON解析
    $tests[] = [
        'name' => 'test_recursion_json.php',
        'desc' => '递归JSON解析',
        'code' => '<?php
function countJsonDepth($data, $depth = 0) {
    if (!is_array($data)) {
        return $depth;
    }
    if (empty($data)) {
        return $depth;
    }
    $max = $depth;
    foreach ($data as $value) {
        $d = countJsonDepth($value, $depth + 1);
        if ($d > $max) {
            $max = $d;
        }
    }
    return $max;
}

$jsonStrings = [
    \'{"a": 1}\',
    \'{"a": {"b": 2}}\',
    \'{"a": {"b": {"c": {"d": 1}}}}\',
    \'[1, [2, [3, [4]]]]\',
];

foreach ($jsonStrings as $json) {
    $data = json_decode($json, true);
    echo "Depth of $json: " . countJsonDepth($data) . "\n";
}
'
    ];

    foreach ($tests as $test) {
        file_put_contents($output_dir . $test['name'], $test['code']);
        echo "Generated: " . $test['name'] . " ({$test['desc']})\n";
    }
}

/**
 * 生成对象引用测试
 */
function generateObjectReferenceTests($output_dir) {
    $tests = [];

    // 测试1：对象引用传递
    $tests[] = [
        'name' => 'test_object_ref_pass.php',
        'desc' => '对象引用传递',
        'code' => '<?php
class Counter {
    public $count = 0;
}

function increment($counter) {
    $counter->count++;
    return $counter;
}

$counter = new Counter();
$counter = increment($counter);
$counter = increment($counter);
$counter->count++;
echo "Count: " . $counter->count . "\n";
'
    ];

    // 测试2：对象引用修改
    $tests[] = [
        'name' => 'test_object_ref_modify.php',
        'desc' => '对象引用修改',
        'code' => '<?php
class Data {
    public $value = 0;
}

function modify(&$obj) {
    $obj->value = 100;
}

$data = new Data();
modify($data);
echo "Value: " . $data->value . "\n";
'
    ];

    // 测试3：对象数组引用
    $tests[] = [
        'name' => 'test_object_array_ref.php',
        'desc' => '对象数组引用',
        'code' => '<?php
class Item {
    public $name;
    public $price;

    public function __construct($name, $price) {
        $this->name = $name;
        $this->price = $price;
    }
}

$items = [
    new Item("Apple", 1.50),
    new Item("Banana", 0.75),
    new Item("Cherry", 2.00),
];

foreach ($items as &$item) {
    $item->price = $item->price * 1.1; // 10% discount
}
unset($item);

echo "Updated prices:\n";
foreach ($items as $item) {
    echo $item->name . ": $" . number_format($item->price, 2) . "\n";
}
'
    ];

    // 测试4：对象克隆
    $tests[] = [
        'name' => 'test_object_clone.php',
        'desc' => '对象克隆',
        'code' => '<?php
class Prototype {
    public $value = 0;
}

$original = new Prototype();
$clone = clone $original;

$original->value = 100;
$clone->value = 200;

echo "Original: " . $original->value . "\n";
echo "Clone: " . $clone->value . "\n";
'
    ];

    // 测试5：对象循环引用
    $tests[] = [
        'name' => 'test_object_cyclic.php',
        'desc' => '对象循环引用',
        'code' => '<?php
class Node {
    public $name;
    public $parent;
    public $children = [];

    public function __construct($name) {
        $this->name = $name;
    }

    public function addChild($child) {
        $this->children[] = $child;
        $child->parent = $this;
    }
}

$root = new Node("Root");
$child1 = new Node("Child1");
$child2 = new Node("Child2");

$root->addChild($child1);
$root->addChild($child2);

echo "Root children count: " . count($root->children) . "\n";
echo "Child1 parent: " . $child1->parent->name . "\n";
echo "Child2 parent: " . $child2->parent->name . "\n";
'
    ];

    // 测试6：对象工厂模式
    $tests[] = [
        'name' => 'test_object_factory.php',
        'desc' => '对象工厂',
        'code' => '<?php
class User {
    public $id;
    public $name;
    public static $counter = 0;

    public function __construct($name) {
        $this->id = ++self::$counter;
        $this->name = $name;
    }
}

function createUser($name) {
    return new User($name);
}

$users = [];
for ($i = 0; $i < 5; $i++) {
    $users[] = createUser("User" . ($i + 1));
}

foreach ($users as $user) {
    echo "User {$user->id}: {$user->name}\n";
}
'
    ];

    // 测试7：对象池模式
    $tests[] = [
        'name' => 'test_object_pool.php',
        'desc' => '对象池',
        'code' => '<?php
class Pool {
    private $pool = [];
    private $class;

    public function __construct($class) {
        $this->class = $class;
    }

    public function get() {
        if (empty($this->pool)) {
            return new $this->class();
        }
        return array_pop($this->pool);
    }

    public function release($obj) {
        $this->pool[] = $obj;
    }
}

class Resource {
    public $id;

    public function __construct() {
        static $counter = 0;
        $this->id = ++$counter;
    }
}

$pool = new Pool(Resource::class);
$r1 = $pool->get();
$r2 = $pool->get();
echo "r1 ID: {$r1->id}\n";
echo "r2 ID: {$r2->id}\n";

$pool->release($r1);
$r3 = $pool->get();
echo "r3 ID (should be same as r1): {$r3->id}\n";
'
    ];

    // 测试8：对象不可变修改
    $tests[] = [
        'name' => 'test_object_immutable.php',
        'desc' => '对象不可变修改',
        'code' => '<?php
class Immutable {
    private $data;

    public function __construct($data) {
        $this->data = $data;
    }

    public function with($key, $value) {
        $new = clone $this;
        $new->data[$key] = $value;
        return $new;
    }

    public function get($key) {
        return $this->data[$key] ?? null;
    }
}

$original = new Immutable(["a" => 1, "b" => 2]);
$modified = $original->with("b", 200);

echo "Original b: " . $original->get("b") . "\n";
echo "Modified b: " . $modified->get("b") . "\n";
'
    ];

    // 测试9：对象数组引用传递
    $tests[] = [
        'name' => 'test_object_array_pass.php',
        'desc' => '对象在数组中传递',
        'code' => '<?php
class Container {
    public $items = [];
}

function addItem($container, $item) {
    $container->items[] = $item;
}

function removeLast($container) {
    array_pop($container->items);
}

$container = new Container();
addItem($container, "A");
addItem($container, "B");
addItem($container, "C");

echo "Items: " . implode(", ", $container->items) . "\n";

removeLast($container);
echo "After remove: " . implode(", ", $container->items) . "\n";
'
    ];

    // 测试10：深度对象引用链
    $tests[] = [
        'name' => 'test_object_deep_chain.php',
        'desc' => '深度对象引用链',
        'code' => '<?php
class Link {
    public $value;
    public $next;

    public function __construct($value, $next = null) {
        $this->value = $value;
        $this->next = $next;
    }
}

function createChain($n) {
    $head = new Link(0);
    $current = $head;
    for ($i = 1; $i < $n; $i++) {
        $current->next = new Link($i);
        $current = $current->next;
    }
    return $head;
}

function sumChain($head) {
    $sum = 0;
    $current = $head;
    while ($current !== null) {
        $sum += $current->value;
        $current = $current->next;
    }
    return $sum;
}

$chain = createChain(100);
echo "Sum of chain: " . sumChain($chain) . "\n";
'
    ];

    foreach ($tests as $test) {
        file_put_contents($output_dir . $test['name'], $test['code']);
        echo "Generated: " . $test['name'] . " ({$test['desc']})\n";
    }
}

/**
 * 生成对象类型判断测试
 */
function generateObjectTypeTests($output_dir) {
    $tests = [];

    // 测试1：instanceof基本使用
    $tests[] = [
        'name' => 'test_type_instanceof.php',
        'desc' => 'instanceof基本使用',
        'code' => '<?php
class A {}
class B extends A {}
class C {}

$a = new A();
$b = new B();
$c = new C();

echo "a instanceof A: " . ($a instanceof A ? "true" : "false") . "\n";
echo "a instanceof B: " . ($a instanceof B ? "true" : "false") . "\n";
echo "b instanceof A: " . ($b instanceof A ? "true" : "false") . "\n";
echo "b instanceof B: " . ($b instanceof B ? "true" : "false") . "\n";
echo "c instanceof A: " . ($c instanceof A ? "true" : "false") . "\n";
'
    ];

    // 测试2：接口instanceof
    $tests[] = [
        'name' => 'test_type_interface.php',
        'desc' => '接口instanceof',
        'code' => '<?php
interface Printable {
    public function print();
}

class Document implements Printable {
    public function print() {
        echo "Document\n";
    }
}

class Image {
    public function display() {
        echo "Image\n";
    }
}

function printIfPrintable($obj) {
    if ($obj instanceof Printable) {
        $obj->print();
    } else {
        echo "Not printable\n";
    }
}

printIfPrintable(new Document());
printIfPrintable(new Image());
'
    ];

    // 测试3：get_class和get_parent_class
    $tests[] = [
        'name' => 'test_type_get_class.php',
        'desc' => 'get_class和get_parent_class',
        'code' => '<?php
class Base {}
class Derived extends Base {}

$obj = new Derived();
echo "Class: " . get_class($obj) . "\n";
echo "Parent: " . get_parent_class($obj) . "\n";
echo "Parent of Base: " . get_parent_class("Base") . "\n";
'
    ];

    // 测试4：is_a和is_subclass_of
    $tests[] = [
        'name' => 'test_type_is_a.php',
        'desc' => 'is_a和is_subclass_of',
        'code' => '<?php
class Animal {}
class Dog extends Animal {}

$dog = new Dog();

echo "is_a(dog, Dog): " . (is_a($dog, "Dog") ? "true" : "false") . "\n";
echo "is_a(dog, Animal): " . (is_a($dog, "Animal") ? "true" : "false") . "\n";
echo "is_subclass_of(dog, Dog): " . (is_subclass_of($dog, "Dog") ? "true" : "false") . "\n";
echo "is_subclass_of(dog, Animal): " . (is_subclass_of($dog, "Animal") ? "true" : "false") . "\n";
'
    ];

    // 测试5：trait instanceof
    $tests[] = [
        'name' => 'test_type_trait.php',
        'desc' => 'trait instanceof',
        'code' => '<?php
trait Loggable {
    public function log($msg) {
        echo $msg . "\n";
    }
}

class User {
    use Loggable;
}

class Product {
    use Loggable;
}

$user = new User();
$product = new Product();

$user->log("User logged in");
$product->log("Product viewed");
'
    ];

    // 测试6：匿名类类型判断
    $tests[] = [
        'name' => 'test_type_anonymous.php',
        'desc' => '匿名类类型判断',
        'code' => '<?php
$object = new class {};

echo "Anonymous class: " . get_class($object) . "\n";
echo "Is object: " . (is_object($object) ? "true" : "false") . "\n";
'
    ];

    // 测试7：多态类型判断
    $tests[] = [
        'name' => 'test_type_polymorphism.php',
        'desc' => '多态类型判断',
        'code' => '<?php
abstract class Shape {
    abstract public function area();
}

class Circle extends Shape {
    private $radius;

    public function __construct($radius) {
        $this->radius = $radius;
    }

    public function area() {
        return pi() * $this->radius * $this->radius;
    }
}

class Rectangle extends Shape {
    private $width, $height;

    public function __construct($width, $height) {
        $this->width = $width;
        $this->height = $height;
    }

    public function area() {
        return $this->width * $this->height;
    }
}

$shapes = [
    new Circle(5),
    new Rectangle(4, 6),
    new Circle(3),
];

foreach ($shapes as $shape) {
    $type = get_class($shape);
    $area = $shape->area();
    echo "$type area: " . number_format($area, 2) . "\n";
}
'
    ];

    // 测试8：接口多态
    $tests[] = [
        'name' => 'test_type_interface_poly.php',
        'desc' => '接口多态',
        'code' => '<?php
interface Storage {
    public function save($data);
    public function load();
}

class FileStorage implements Storage {
    private $file = "/tmp/data.txt";

    public function save($data) {
        file_put_contents($this->file, $data);
    }

    public function load() {
        return file_get_contents($this->file);
    }
}

class MemoryStorage implements Storage {
    private $data = "";

    public function save($data) {
        $this->data = $data;
    }

    public function load() {
        return $this->data;
    }
}

function useStorage(Storage $storage) {
    $storage->save("Hello World");
    echo "Loaded: " . $storage->load() . "\n";
}

useStorage(new FileStorage());
useStorage(new MemoryStorage());
'
    ];

    // 测试9：复合类型判断
    $tests[] = [
        'name' => 'test_type_compound.php',
        'desc' => '复合类型判断',
        'code' => '<?php
function checkType($value) {
    $checks = [
        "is_null" => is_null($value),
        "is_bool" => is_bool($value),
        "is_int" => is_int($value),
        "is_float" => is_float($value),
        "is_string" => is_string($value),
        "is_array" => is_array($value),
        "is_object" => is_object($value),
        "is_resource" => is_resource($value),
        "is_callable" => is_callable($value),
    ];

    foreach ($checks as $check => $result) {
        if ($result) {
            echo "$check: true\n";
        }
    }
}

checkType(null);
checkType(true);
checkType(42);
checkType(3.14);
checkType("hello");
checkType([1, 2, 3]);
checkType(new stdClass());
'
    ];

    // 测试10：强制类型转换
    $tests[] = [
        'name' => 'test_type_cast.php',
        'desc' => '强制类型转换',
        'code' => '<?php
$values = [
    "42",
    "3.14",
    "true",
    "false",
    "null",
    "123abc",
    "abc123",
];

foreach ($values as $value) {
    echo "Value: $value\n";
    echo "  (int): " . (int)$value . "\n";
    echo "  (float): " . (float)$value . "\n";
    echo "  (string): " . (string)$value . "\n";
    echo "  (bool): " . ((bool)$value ? "true" : "false") . "\n";
    echo "  (array): " . json_encode((array)$value) . "\n";
    echo "\n";
}
'
    ];

    foreach ($tests as $test) {
        file_put_contents($output_dir . $test['name'], $test['code']);
        echo "Generated: " . $test['name'] . " ({$test['desc']})\n";
    }
}

/**
 * 生成数组操作测试
 */
function generateArrayTests($output_dir) {
    $tests = [];

    // 测试1：多维数组操作
    $tests[] = [
        'name' => 'test_array_multidimensional.php',
        'desc' => '多维数组操作',
        'code' => '<?php
$matrix = [
    [1, 2, 3],
    [4, 5, 6],
    [7, 8, 9],
];

echo "Matrix:\n";
foreach ($matrix as $row) {
    echo implode(" ", $row) . "\n";
}

echo "Diagonal: ";
echo $matrix[0][0] . ", " . $matrix[1][1] . ", " . $matrix[2][2] . "\n";

// Transpose
$transposed = [];
for ($i = 0; $i < 3; $i++) {
    for ($j = 0; $j < 3; $j++) {
        $transposed[$i][$j] = $matrix[$j][$i];
    }
}

echo "Transposed:\n";
foreach ($transposed as $row) {
    echo implode(" ", $row) . "\n";
}
'
    ];

    // 测试2：array_map和array_filter
    $tests[] = [
        'name' => 'test_array_map_filter.php',
        'desc' => 'array_map和array_filter',
        'code' => '<?php
$numbers = range(1, 20);

// Filter even numbers
$evens = array_filter($numbers, function($n) {
    return $n % 2 == 0;
});

// Map to square
$squares = array_map(function($n) {
    return $n * $n;
}, $evens);

echo "Original: " . implode(", ", $numbers) . "\n";
echo "Evens: " . implode(", ", $evens) . "\n";
echo "Squares: " . implode(", ", $squares) . "\n";
'
    ];

    // 测试3：array_reduce
    $tests[] = [
        'name' => 'test_array_reduce.php',
        'desc' => 'array_reduce',
        'code' => '<?php
$numbers = [1, 2, 3, 4, 5, 6, 7, 8, 9, 10];

$sum = array_reduce($numbers, function($carry, $item) {
    return $carry + $item;
}, 0);

$product = array_reduce($numbers, function($carry, $item) {
    return $carry * $item;
}, 1);

$concat = array_reduce($numbers, function($carry, $item) {
    return $carry . $item;
}, "");

echo "Sum: $sum\n";
echo "Product: $product\n";
echo "Concat: $concat\n";
'
    ];

    // 测试4：array_walk
    $tests[] = [
        'name' => 'test_array_walk.php',
        'desc' => 'array_walk',
        'code' => '<?php
$fruits = ["apple" => 1.50, "banana" => 0.75, "cherry" => 2.00];

echo "Original:\n";
array_walk($fruits, function($price, $name) {
    echo "$name: \$$price\n";
});

// With reference
array_walk($fruits, function(&$price, $name) {
    $price = round($price * 1.1, 2); // 10% tax
});

echo "After tax:\n";
array_walk($fruits, function($price, $name) {
    echo "$name: \$$price\n";
});
'
    ];

    // 测试5：sorting arrays
    $tests[] = [
        'name' => 'test_array_sort.php',
        'desc' => '数组排序',
        'code' => '<?php
$numbers = [5, 2, 8, 1, 9, 3, 7, 4, 6];
$words = ["apple", "banana", "cherry", "date", "elderberry"];

echo "Numbers: " . implode(", ", $numbers) . "\n";
sort($numbers);
echo "Sorted: " . implode(", ", $numbers) . "\n";

echo "Words: " . implode(", ", $words) . "\n";
sort($words);
echo "Sorted: " . implode(", ", $words) . "\n";

// Associative array
$prices = ["apple" => 1.50, "banana" => 0.75, "cherry" => 2.00];
asort($prices);
echo "Prices (asort): ";
print_r($prices);

ksort($prices);
echo "Prices (ksort): ";
print_r($prices);
'
    ];

    // 测试6：array_merge和array_combine
    $tests[] = [
        'name' => 'test_array_merge.php',
        'desc' => 'array_merge和array_combine',
        'code' => '<?php
$arr1 = ["a", "b", "c"];
$arr2 = [1, 2, 3];

$merged = array_merge($arr1, $arr2);
echo "Merged: " . implode(", ", $merged) . "\n";

$keys = ["name", "age", "city"];
$values = ["John", 30, "NYC"];

$combined = array_combine($keys, $values);
echo "Combined: ";
print_r($combined);
'
    ];

    // 测试7：array_slice和array_splice
    $tests[] = [
        'name' => 'test_array_slice.php',
        'desc' => 'array_slice和array_splice',
        'code' => '<?php
$items = [1, 2, 3, 4, 5, 6, 7, 8, 9, 10];

$middle = array_slice($items, 3, 4);
echo "Middle (slice): " . implode(", ", $middle) . "\n";

$copy = $items;
array_splice($copy, 3, 4, [30, 40, 50]);
echo "After splice: " . implode(", ", $copy) . "\n";
'
    ];

    // 测试8：array_search和in_array
    $tests[] = [
        'name' => 'test_array_search.php',
        'desc' => 'array_search和in_array',
        'code' => '<?php
$array = ["apple", "banana", "cherry", "date", "banana"];

$pos = array_search("banana", $array);
echo "First banana at: $pos\n";

$pos = array_search("banana", $array, true);
echo "First banana (strict) at: $pos\n";

echo "Has mango: " . (in_array("mango", $array) ? "yes" : "no") . "\n";
echo "Has banana: " . (in_array("banana", $array) ? "yes" : "no") . "\n";
'
    ];

    // 测试9：groupBy模式
    $tests[] = [
        'name' => 'test_array_group.php',
        'desc' => '数组分组',
        'code' => '<?php
$people = [
    ["name" => "Alice", "age" => 25, "city" => "NYC"],
    ["name" => "Bob", "age" => 30, "city" => "LA"],
    ["name" => "Charlie", "age" => 25, "city" => "NYC"],
    ["name" => "Diana", "age" => 30, "city" => "LA"],
    ["name" => "Eve", "age" => 35, "city" => "NYC"],
];

// Group by age
$byAge = [];
foreach ($people as $person) {
    $age = $person["age"];
    if (!isset($byAge[$age])) {
        $byAge[$age] = [];
    }
    $byAge[$age][] = $person["name"];
}

echo "By age:\n";
foreach ($byAge as $age => $names) {
    echo "  Age $age: " . implode(", ", $names) . "\n";
}
'
    ];

    // 测试10：数组交集差集
    $tests[] = [
        'name' => 'test_array_set.php',
        'desc' => '数组交集差集',
        'code' => '<?php
$a = [1, 2, 3, 4, 5];
$b = [3, 4, 5, 6, 7];

echo "A: " . implode(", ", $a) . "\n";
echo "B: " . implode(", ", $b) . "\n";
echo "Intersection: " . implode(", ", array_intersect($a, $b)) . "\n";
echo "Union: " . implode(", ", array_unique(array_merge($a, $b))) . "\n";
echo "A - B: " . implode(", ", array_diff($a, $b)) . "\n";
echo "B - A: " . implode(", ", array_diff($b, $a)) . "\n";
echo "XOR: " . implode(", ", array_diff(array_merge($a, $b), array_intersect($a, $b))) . "\n";
'
    ];

    foreach ($tests as $test) {
        file_put_contents($output_dir . $test['name'], $test['code']);
        echo "Generated: " . $test['name'] . " ({$test['desc']})\n";
    }
}

/**
 * 生成函数参数测试
 */
function generateFunctionParamTests($output_dir) {
    $tests = [];

    // 测试1：默认参数
    $tests[] = [
        'name' => 'test_param_default.php',
        'desc' => '默认参数',
        'code' => '<?php
function greet($name = "World", $greeting = "Hello") {
    return "$greeting, $name!";
}

echo greet() . "\n";
echo greet("Alice") . "\n";
echo greet("Bob", "Hi") . "\n";
echo greet("Charlie", "Good morning") . "\n";
'
    ];

    // 测试2：类型声明
    $tests[] = [
        'name' => 'test_param_type.php',
        'desc' => '类型声明',
        'code' => '<?php
function add(int $a, int $b): int {
    return $a + $b;
}

function concat(string $a, string $b): string {
    return $a . $b;
}

function double(array $arr): array {
    return array_map(function($x) { return $x * 2; }, $arr);
}

echo add(1, 2) . "\n";
echo concat("Hello", "World") . "\n";
print_r(double([1, 2, 3]));
'
    ];

    // 测试3：可变参数
    $tests[] = [
        'name' => 'test_param_variadic.php',
        'desc' => '可变参数',
        'code' => '<?php
function sum(...$numbers): int {
    return array_sum($numbers);
}

function concatenate(...$strings): string {
    return implode("", $strings);
}

function mixedArgs($required, $optional = null, ...$variadic) {
    echo "Required: $required\n";
    echo "Optional: " . ($optional ?? "null") . "\n";
    echo "Variadic: " . implode(", ", $variadic) . "\n";
}

echo "Sum: " . sum(1, 2, 3, 4, 5) . "\n";
mixedArgs("A", "B", "C", "D", "E");
'
    ];

    // 测试4：引用参数
    $tests[] = [
        'name' => 'test_param_reference.php',
        'desc' => '引用参数',
        'code' => '<?php
function increment(&$value, $by = 1) {
    $value += $by;
    return $value;
}

$x = 10;
increment($x);
echo "After increment: $x\n";
increment($x, 5);
echo "After increment by 5: $x\n";
'
    ];

    // 测试5：回调函数
    $tests[] = [
        'name' => 'test_param_callback.php',
        'desc' => '回调函数',
        'code' => '<?php
function apply($value, $callback) {
    return $callback($value);
}

echo apply(5, function($x) { return $x * $x; }) . "\n";
echo apply("hello", "strlen") . "\n";

function doOperation($a, $b, $operation) {
    return $operation($a, $b);
}

$add = function($x, $y) { return $x + $y; };
echo doOperation(10, 20, $add) . "\n";
'
    ];

    // 测试6：可调用类型
    $tests[] = [
        'name' => 'test_param_callable.php',
        'desc' => '可调用类型',
        'code' => '<?php
class Math {
    public function add($a, $b) {
        return $a + $b;
    }

    public static function multiply($a, $b) {
        return $a * $b;
    }
}

function execute(callable $func, ...$args) {
    return $func(...$args);
}

$math = new Math();
echo execute([$math, "add"], 5, 10) . "\n";
echo execute([Math::class, "multiply"], 5, 10) . "\n";
echo execute("sqrt", 16) . "\n";
'
    ];

    // 测试7：命名参数
    $tests[] = [
        'name' => 'test_param_named.php',
        'desc' => '命名参数',
        'code' => '<?php
function createUser($name, $age, $city, $email) {
    return [
        "name" => $name,
        "age" => $age,
        "city" => $city,
        "email" => $email
    ];
}

$user = createUser(
    name: "Alice",
    age: 30,
    city: "NYC",
    email: "alice@example.com"
);

print_r($user);
'
    ];

    // 测试8：混合参数类型
    $tests[] = [
        'name' => 'test_param_mixed.php',
        'desc' => '混合参数类型',
        'code' => '<?php
function complexFunction(
    int $int,
    float $float,
    string $string,
    array $array,
    ?string $nullable = null
) {
    echo "int: $int\n";
    echo "float: $float\n";
    echo "string: $string\n";
    echo "array count: " . count($array) . "\n";
    echo "nullable: " . ($nullable ?? "null") . "\n";
}

complexFunction(42, 3.14, "hello", [1, 2, 3]);
'
    ];

    // 测试9：闭包作为默认参数
    $tests[] = [
        'name' => 'test_param_closure_default.php',
        'desc' => '闭包作为默认参数',
        'code' => '<?php
function createMultiplier($factor) {
    return function($value) use ($factor) {
        return $value * $factor;
    };
}

$double = createMultiplier(2);
$triple = createMultiplier(3);

echo $double(5) . "\n";
echo $triple(5) . "\n";
'
    ];

    // 测试10：参数解包
    $tests[] = [
        'name' => 'test_param_unpack.php',
        'desc' => '参数解包',
        'code' => '<?php
function sum($a, $b, $c) {
    return $a + $b + $c;
}

$numbers = [1, 2, 3];
echo "Sum: " . sum(...$numbers) . "\n";

function logMessage($level, $message, $context = []) {
    echo "[$level] $message\n";
    if (!empty($context)) {
        echo "Context: " . json_encode($context) . "\n";
    }
}

$context = ["user" => "Alice", "action" => "login"];
logMessage("INFO", "User logged in", ...$context);
'
    ];

    foreach ($tests as $test) {
        file_put_contents($output_dir . $test['name'], $test['code']);
        echo "Generated: " . $test['name'] . " ({$test['desc']})\n";
    }
}

/**
 * 生成混合复杂测试
 */
function generateMixedTests($output_dir) {
    $tests = [];

    // 测试1：复杂对象+递归
    $tests[] = [
        'name' => 'test_mixed_graph.php',
        'desc' => '图遍历（对象+递归）',
        'code' => '<?php
class GraphNode {
    public $name;
    public $neighbors = [];

    public function __construct($name) {
        $this->name = $name;
    }

    public function addNeighbor($node) {
        $this->neighbors[] = $node;
    }
}

function dfs($node, &$visited = [], $depth = 0) {
    if (isset($visited[$node->name])) {
        return;
    }
    $visited[$node->name] = true;
    echo str_repeat("  ", $depth) . $node->name . "\n";
    foreach ($node->neighbors as $neighbor) {
        dfs($neighbor, $visited, $depth + 1);
    }
}

function bfs($start) {
    $queue = [$start];
    $visited = [$start->name => true];
    $depth = 0;

    while (!empty($queue)) {
        $levelSize = count($queue);
        echo "Level $depth: ";
        for ($i = 0; $i < $levelSize; $i++) {
            $node = array_shift($queue);
            echo $node->name . " ";
            foreach ($node->neighbors as $neighbor) {
                if (!isset($visited[$neighbor->name])) {
                    $visited[$neighbor->name] = true;
                    $queue[] = $neighbor;
                }
            }
        }
        echo "\n";
        $depth++;
    }
}

$a = new GraphNode("A");
$b = new GraphNode("B");
$c = new GraphNode("C");
$d = new GraphNode("D");
$e = new GraphNode("E");

$a->addNeighbor($b);
$a->addNeighbor($c);
$b->addNeighbor($d);
$c->addNeighbor($d);
$d->addNeighbor($e);

echo "DFS:\n";
dfs($a);

echo "\nBFS:\n";
bfs($a);
'
    ];

    // 测试2：复杂数组操作+回调
    $tests[] = [
        'name' => 'test_mixed_pipeline.php',
        'desc' => '数据处理管道',
        'code' => '<?php
$data = [
    ["name" => "Alice", "age" => 25, "score" => 85],
    ["name" => "Bob", "age" => 30, "score" => 92],
    ["name" => "Charlie", "age" => 22, "score" => 78],
    ["name" => "Diana", "age" => 28, "score" => 95],
    ["name" => "Eve", "age" => 35, "score" => 88],
];

$pipeline = [
    "filter_score" => fn($items) => array_filter($items, fn($item) => $item["score"] >= 80),
    "sort_by_score" => fn($items) => usort($items, fn($a, $b) => $b["score"] - $a["score"]) ?: 0),
    "map_names" => fn($items) => array_map(fn($item) => $item["name"], $items),
    "implode" => fn($items) => implode(", ", $items),
];

$result = $data;
foreach ($pipeline as $name => $transform) {
    $result = $transform($result);
}

echo "Result: $result\n";
'
    ];

    // 测试3：对象工厂+依赖注入
    $tests[] = [
        'name' => 'test_mixed_factory.php',
        'desc' => '对象工厂+依赖注入',
        'code' => '<?php
interface Logger {
    public function log($message);
}

class FileLogger implements Logger {
    private $file;

    public function __construct($file) {
        $this->file = $file;
    }

    public function log($message) {
        echo "[File] $message\n";
    }
}

class ConsoleLogger implements Logger {
    public function log($message) {
        echo "[Console] $message\n";
    }
}

class Service {
    private $logger;

    public function __construct(Logger $logger) {
        $this->logger = $logger;
    }

    public function doSomething($task) {
        $this->logger->log("Starting: $task");
        // Simulate work
        $result = strtoupper($task);
        $this->logger->log("Completed: $result");
        return $result;
    }
}

function createService($loggerType) {
    $logger = $loggerType === "file" ? new FileLogger("app.log") : new ConsoleLogger();
    return new Service($logger);
}

$service1 = createService("file");
$service2 = createService("console");

echo "=== File Logger Service ===\n";
$service1->doSomething("process data");

echo "\n=== Console Logger Service ===\n";
$service2->doSomething("send email");
'
    ];

    // 测试4：闭包记忆化+递归
    $tests[] = [
        'name' => 'test_mixed_memoization.php',
        'desc' => '闭包记忆化',
        'code' => '<?php
function memoize($callback) {
    $cache = [];
    return function(...$args) use (&$cache, $callback) {
        $key = json_encode($args);
        if (isset($cache[$key])) {
            return $cache[$key];
        }
        $result = $callback(...$args);
        $cache[$key] = $result;
        return $result;
    };
}

$fibMemo = memoize(function($n) use (&$fibMemo) {
    if ($n <= 1) return $n;
    return $fibMemo($n - 1) + $fibMemo($n - 2);
});

echo "Fibonacci (memoized):\n";
for ($i = 0; $i <= 20; $i++) {
    echo "fib($i) = " . $fibMemo($i) . "\n";
}
'
    ];

    // 测试5：事件系统
    $tests[] = [
        'name' => 'test_mixed_event.php',
        'desc' => '事件系统',
        'code' => '<?php
class EventEmitter {
    private $listeners = [];

    public function on($event, $callback) {
        $this->listeners[$event][] = $callback;
    }

    public function emit($event, ...$args) {
        if (isset($this->listeners[$event])) {
            foreach ($this->listeners[$event] as $listener) {
                $listener(...$args);
            }
        }
    }
}

$emitter = new EventEmitter();

$emitter->on("user.created", function($user) {
    echo "Welcome, " . $user["name"] . "!\n";
});

$emitter->on("user.created", function($user) {
    echo "Sending email to " . $user["email"] . "...\n";
});

$emitter->on("order.placed", function($order) {
    echo "Order #" . $order["id"] . " placed!\n";
});

$emitter->emit("user.created", [
    "name" => "Alice",
    "email" => "alice@example.com"
]);

$emitter->emit("order.placed", [
    "id" => 12345,
    "total" => 99.99
]);
'
    ];

    // 测试6：迭代器模式
    $tests[] = [
        'name' => 'test_mixed_iterator.php',
        'desc' => '迭代器模式',
        'code' => '<?php
class Range implements Iterator {
    private $start;
    private $end;
    private $current;

    public function __construct($start, $end) {
        $this->start = $start;
        $this->end = $end;
        $this->current = $start;
    }

    public function rewind() {
        $this->current = $this->start;
    }

    public function current() {
        return $this->current;
    }

    public function key() {
        return $this->current;
    }

    public function next() {
        $this->current++;
    }

    public function valid() {
        return $this->current <= $this->end;
    }
}

class Composite implements IteratorAggregate {
    private $items = [];

    public function add($item) {
        $this->items[] = $item;
    }

    public function getIterator() {
        return new ArrayIterator($this->items);
    }
}

echo "Range iterator:\n";
foreach (new Range(1, 5) as $num) {
    echo "$num ";
}
echo "\n";

$composite = new Composite();
$composite->add("A");
$composite->add("B");
$composite->add("C");

echo "Composite iterator:\n";
foreach ($composite as $item) {
    echo "$item ";
}
echo "\n";
'
    ];

    // 测试7：状态机
    $tests[] = [
        'name' => 'test_mixed_state_machine.php',
        'desc' => '状态机',
        'code' => '<?php
class StateMachine {
    private $states = [];
    private $current;
    private $transitions = [];

    public function addState($name) {
        $this->states[] = $name;
        if ($this->current === null) {
            $this->current = $name;
        }
    }

    public function addTransition($from, $to, $action) {
        $this->transitions[$from][$to] = $action;
    }

    public function canTransition($to) {
        return isset($this->transitions[$this->current][$to]);
    }

    public function transition($to) {
        if ($this->canTransition($to)) {
            $action = $this->transitions[$this->current][$to];
            $action();
            $this->current = $to;
            return true;
        }
        return false;
    }

    public function getState() {
        return $this->current;
    }
}

$machine = new StateMachine();
$machine->addState("pending");
$machine->addState("processing");
$machine->addState("completed");
$machine->addState("failed");

$machine->addTransition("pending", "processing", fn() => echo "Starting process...\n");
$machine->addTransition("processing", "completed", fn() => echo "Process done!\n");
$machine->addTransition("processing", "failed", fn() => echo "Process failed!\n");
$machine->addTransition("failed", "pending", fn() => echo "Retrying...\n");

echo "Initial state: " . $machine->getState() . "\n";
$machine->transition("processing");
echo "After transition: " . $machine->getState() . "\n";
$machine->transition("completed");
echo "Final state: " . $machine->getState() . "\n";
'
    ];

    // 测试8：链表+高阶函数
    $tests[] = [
        'name' => 'test_mixed_linked_list.php',
        'desc' => '链表+高阶函数',
        'code' => '<?php
class LinkedList {
    private $head = null;

    public function add($value) {
        $node = ["value" => $value, "next" => $this->head];
        $this->head = &$node;
    }

    public function map($callback) {
        $result = new LinkedList();
        $current = &$this->head;
        while ($current !== null) {
            $result->add($callback($current["value"]));
            $current = &$current["next"];
        }
        return $result;
    }

    public function filter($callback) {
        $result = new LinkedList();
        $current = &$this->head;
        while ($current !== null) {
            if ($callback($current["value"])) {
                $result->add($current["value"]);
            }
            $current = &$current["next"];
        }
        return $result;
    }

    public function reduce($callback, $initial) {
        $accumulator = $initial;
        $current = &$this->head;
        while ($current !== null) {
            $accumulator = $callback($accumulator, $current["value"]);
            $current = &$current["next"];
        }
        return $accumulator;
    }

    public function toArray() {
        $result = [];
        $current = &$this->head;
        while ($current !== null) {
            $result[] = $current["value"];
            $current = &$current["next"];
        }
        return array_reverse($result);
    }
}

$list = new LinkedList();
for ($i = 1; $i <= 5; $i++) {
    $list->add($i);
}

$doubled = $list->map(fn($x) => $x * 2);
echo "Doubled: " . implode(", ", $doubled->toArray()) . "\n";

$filtered = $list->filter(fn($x) => $x % 2 == 1);
echo "Odd: " . implode(", ", $filtered->toArray()) . "\n";

$sum = $list->reduce(fn($carry, $item) => $carry + $item, 0);
echo "Sum: $sum\n";
'
    ];

    // 测试9：组合函数
    $tests[] = [
        'name' => 'test_mixed_compose.php',
        'desc' => '函数组合',
        'code' => '<?php
function compose(...$functions) {
    return function($value) use ($functions) {
        $result = $value;
        foreach ($functions as $function) {
            $result = $function($result);
        }
        return $result;
    };
}

$f1 = fn($x) => $x + 1;
$f2 = fn($x) => $x * 2;
$f3 = fn($x) => $x ** 2;

$composed = compose($f1, $f2, $f3);

echo "compose(f1, f2, f3)(5) = " . $composed(5) . "\n";
echo "Manual: f3(f2(f1(5))) = " . $f3($f2($f1(5))) . "\n";
'
    ];

    // 测试10：柯里化
    $tests[] = [
        'name' => 'test_mixed_curry.php',
        'desc' => '柯里化',
        'code' => '<?php
function curry($callback, $arity = null) {
    if ($arity === null) {
        $arity = (new ReflectionFunction($callback))->getNumberOfParameters();
    }

    return function use ($callback, $arity) {
        return function(...$args) use ($callback, $arity, $args) {
            if (count($args) >= $arity) {
                return $callback(...$args);
            }
            return curry(fn(...$more) => $callback(...$args, ...$more), $arity - count($args));
        };
    }();
}

$add = curry(fn($a, $b, $c) => $a + $b + $c);

$add5 = $add(5);
$add5and10 = $add5(10);
$result = $add5and10(3);

echo "curry(add)(5)(10)(3) = $result\n";
'
    ];

    foreach ($tests as $test) {
        file_put_contents($output_dir . $test['name'], $test['code']);
        echo "Generated: " . $test['name'] . " ({$test['desc']})\n";
    }
}

// 生成所有测试
echo "=== 生成复杂功能测试脚本 ===\n\n";

echo "1. 递归测试:\n";
generateRecursionTests($output_dir . 'recursion/');

echo "\n2. 对象引用测试:\n";
generateObjectReferenceTests($output_dir . 'object_reference/');

echo "\n3. 对象类型判断测试:\n";
generateObjectTypeTests($output_dir . 'object_type/');

echo "\n4. 数组操作测试:\n";
generateArrayTests($output_dir . 'arrays/');

echo "\n5. 函数参数测试:\n";
generateFunctionParamTests($output_dir . 'function_params/');

echo "\n6. 混合复杂测试:\n";
generateMixedTests($output_dir . 'mixed/');

echo "\n=== 完成! 生成了大量复杂功能测试脚本 ===\n";
