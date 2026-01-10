<?php
/**
 * Comprehensive OOP Test - Memory Leaks and Functionality Verification
 * Tests complex scenarios including:
 * - Circular references
 * - Self-referencing objects
 * - Closures capturing objects
 * - Exception handling with objects
 * - Object arrays and iteration
 * - Static properties and singleton
 * - Object cloning
 * - Reflection operations
 * - Dynamic property manipulation
 * - Observer pattern
 * - Dependency injection
 * - Factory patterns
 * - Object pools
 */

echo "=== Comprehensive OOP Test Suite ===\n\n";

// ============================================================================
// Test 1: Circular References (Critical for memory leaks)
// ============================================================================
echo "--- Test 1: Circular References ---\n";

class Node {
    public $id;
    public $name;
    public $parent;
    public $children = [];
    
    public function __construct($id, $name) {
        $this->id = $id;
        $this->name = $name;
    }
    
    public function addChild(Node $child) {
        $this->children[] = $child;
        $child->parent = $this;
    }
    
    public function getChildren() {
        return $this->children;
    }
}

class CircularRefA {
    public $id;
    public $partner;
    public $data;
    
    public function __construct($id) {
        $this->id = $id;
        $this->data = str_repeat("data{$id}_", 100);
    }
    
    public function setPartner(CircularRefB $partner) {
        $this->partner = $partner;
    }
}

class CircularRefB {
    public $id;
    public $partner;
    public $data;
    
    public function __construct($id) {
        $this->id = $id;
        $this->data = str_repeat("data{$id}_", 100);
    }
    
    public function setPartner(CircularRefA $partner) {
        $this->partner = $partner;
    }
}

// Tree structure with bidirectional links
$root = new Node(1, "Root");
$child1 = new Node(2, "Child1");
$child2 = new Node(3, "Child2");
$grandchild1 = new Node(4, "Grandchild1");
$grandchild2 = new Node(5, "Grandchild2");

$root->addChild($child1);
$root->addChild($child2);
$child1->addChild($grandchild1);
$child1->addChild($grandchild2);

echo "Tree created: Root has " . count($root->getChildren()) . " children\n";
echo "Child1 has " . count($child1->getChildren()) . " children\n";

// Circular references between objects
$a = new CircularRefA("A");
$b = new CircularRefB("B");
$a->setPartner($b);
$b->setPartner($a);

echo "Circular reference created between A and B\n";
echo "A.partner.id = {$a->partner->id}\n";
echo "B.partner.id = {$b->partner->id}\n";

// ============================================================================
// Test 2: Self-Referencing Objects
// ============================================================================
echo "\n--- Test 2: Self-Referencing Objects ---\n";

class SelfReferencingNode {
    public $id;
    public $data;
    public $next;
    
    public function __construct($id, $data) {
        $this->id = $id;
        $this->data = $data;
        $this->next = null;
    }
}

// Create linked list with many nodes
$head = new SelfReferencingNode(0, "Head");
$current = $head;
for ($i = 1; $i <= 100; $i++) {
    $newNode = new SelfReferencingNode($i, "Node{$i}");
    $current->next = $newNode;
    $current = $newNode;
}

echo "Linked list created with 101 nodes\n";
echo "Last node id: {$current->id}\n";

// Traverse list
$count = 0;
$temp = $head;
while ($temp !== null) {
    $count++;
    $temp = $temp->next;
}
echo "Traversed and counted {$count} nodes\n";

// ============================================================================
// Test 3: Closures Capturing Objects
// ============================================================================
echo "\n--- Test 3: Closures Capturing Objects ---\n";

class ClosureTest {
    public $value;
    public $callback;
    
    public function __construct($value) {
        $this->value = $value;
    }
    
    public function setCallback($callback) {
        $this->callback = $callback;
    }
    
    public function execute() {
        if ($this->callback !== null) {
            return $this->callback($this->value);
        }
        return null;
    }
}

$object1 = new ClosureTest("Object1");
$object2 = new ClosureTest("Object2");
$object3 = new ClosureTest("Object3");

// Closures capturing objects
$object1->setCallback(function($value) use ($object2) {
    return "Callback1: {$value} + {$object2->value}";
});

$object2->setCallback(function($value) use ($object1, $object3) {
    return "Callback2: {$value} + {$object1->value} + {$object3->value}";
});

$object3->setCallback(function($value) {
    return "Callback3: {$value}";
});

echo $object1->execute() . "\n";
echo $object2->execute() . "\n";
echo $object3->execute() . "\n";

// Array of closures
$closureArray = [];
for ($i = 0; $i < 50; $i++) {
    $tempObj = new ClosureTest("Temp{$i}");
    $closureArray[] = function() use ($tempObj) {
        return $tempObj->value;
    };
}

echo "Created array of 50 closures with captured objects\n";

// ============================================================================
// Test 4: Exception Handling with Objects
// ============================================================================
echo "\n--- Test 4: Exception Handling with Objects ---\n";

class CustomException extends Exception {
    private $context;
    
    public function __construct($message, $context = null) {
        parent::__construct($message);
        $this->context = $context;
    }
    
    public function getContext() {
        return $this->context;
    }
}

class ObjectWithException {
    public $data;
    
    public function __construct($data) {
        $this->data = $data;
    }
    
    public function throwWithObject() {
        throw new CustomException("Error with object context", $this);
    }
    
    public function throwNested() {
        $inner = new ObjectWithException("Inner");
        throw new CustomException("Nested error", $inner);
    }
}

$exceptionObj = new ObjectWithException("TestData");

try {
    $exceptionObj->throwWithObject();
} catch (CustomException $e) {
    echo "Caught exception: {$e->getMessage()}\n";
    $context = $e->getContext();
    if ($context !== null) {
        echo "Exception context data: {$context->data}\n";
    }
}

try {
    $exceptionObj->throwNested();
} catch (CustomException $e) {
    echo "Caught nested exception: {$e->getMessage()}\n";
    $inner = $e->getContext();
    if ($inner !== null) {
        echo "Inner object data: {$inner->data}\n";
    }
}

// ============================================================================
// Test 5: Object Arrays and Iteration
// ============================================================================
echo "\n--- Test 5: Object Arrays and Iteration ---\n";

class Item {
    public $id;
    public $name;
    public $value;
    
    public function __construct($id, $name, $value) {
        $this->id = $id;
        $this->name = $name;
        $this->value = $value;
    }
    
    public function getValue() {
        return $this->value;
    }
}

// Create large array of objects
$items = [];
for ($i = 0; $i < 200; $i++) {
    $items[] = new Item($i, "Item{$i}", $i * 10);
}

echo "Created array with 200 items\n";

// Filter and transform
$filtered = array_filter($items, function($item) {
    return $item->id % 2 == 0;
});

echo "Filtered to " . count($filtered) . " even items\n";

// Map/transform
$mapped = array_map(function($item) {
    return $item->name . ": " . ($item->value * 2);
}, $items);

echo "First 5 mapped values: " . implode(", ", array_slice($mapped, 0, 5)) . "\n";

// Reduce
$sum = array_reduce($items, function($carry, $item) {
    return $carry + $item->value;
}, 0);

echo "Sum of all values: {$sum}\n";

// ============================================================================
// Test 6: Static Properties and Singleton
// ============================================================================
echo "\n--- Test 6: Static Properties and Singleton ---\n";

class Singleton {
    private static $instance = null;
    private static $instances = 0;
    private $id;
    private $data = [];
    
    private function __construct($id) {
        $this->id = $id;
    }
    
    public static function getInstance($id = "default") {
        if (self::$instance === null) {
            self::$instance = new self($id);
            self::$instances = 1;
        }
        return self::$instance;
    }
    
    public static function getInstanceCount() {
        return self::$instances;
    }
    
    public function setData($key, $value) {
        $this->data[$key] = $value;
    }
    
    public function getData($key) {
        return $this->data[$key] ?? null;
    }
    
    public function reset() {
        $this->data = [];
    }
}

class Registry {
    private static $entries = [];
    private static $count = 0;
    
    public static function set($key, $value) {
        self::$entries[$key] = $value;
        self::$count++;
    }
    
    public static function get($key) {
        return self::$entries[$key] ?? null;
    }
    
    public static function getCount() {
        return self::$count;
    }
    
    public static function clear() {
        self::$entries = [];
        self::$count = 0;
    }
}

$singleton = Singleton::getInstance("First");
echo "Singleton instance id: {$singleton->id}\n";

$singleton->setData("key1", "value1");
$singleton->setData("key2", "value2");
$singleton->setData("key3", "value3");

echo "Singleton data count: " . count($singleton->data) . "\n";

// Registry with many entries
for ($i = 0; $i < 100; $i++) {
    $obj = new Item($i, "RegItem{$i}", $i);
    Registry::set("item{$i}", $obj);
}

echo "Registry entries: " . Registry::getCount() . "\n";

// ============================================================================
// Test 7: Object Cloning
// ============================================================================
echo "\n--- Test 7: Object Cloning ---\n";

class DeepCloneTest {
    public $id;
    public $name;
    public $nested;
    
    public function __construct($id, $name) {
        $this->id = $id;
        $this->name = $name;
        $this->nested = new NestedObject($id . "_nested");
    }
    
    public function __clone() {
        $this->nested = clone $this->nested;
    }
}

class NestedObject {
    public $id;
    public $data = [];
    
    public function __construct($id) {
        $this->id = $id;
        for ($i = 0; $i < 10; $i++) {
            $this->data[] = "data{$i}";
        }
    }
}

$original = new DeepCloneTest(1, "Original");
$cloned = clone $original;

echo "Original id: {$original->id}, Nested id: {$original->nested->id}\n";
echo "Cloned id: {$cloned->id}, Nested id: {$cloned->nested->id}\n";

$original->nested->id = "modified";
echo "After modifying original nested:\n";
echo "Original nested id: {$original->nested->id}\n";
echo "Cloned nested id (should be unchanged): {$cloned->nested->id}\n";

// ============================================================================
// Test 8: Reflection Operations
// ============================================================================
echo "\n--- Test 8: Reflection Operations ---\n";

class ReflectionTest {
    private $privateProp;
    protected $protectedProp;
    public $publicProp;
    public static $staticProp = "static";
    
    public function __construct($private, $protected, $public) {
        $this->privateProp = $private;
        $this->protectedProp = $protected;
        $this->publicProp = $public;
    }
    
    private function privateMethod() {
        return "private";
    }
    
    protected function protectedMethod() {
        return "protected";
    }
    
    public function publicMethod() {
        return "public";
    }
    
    public static function staticMethod() {
        return "static";
    }
}

$reflectionTest = new ReflectionTest("private", "protected", "public");

$reflection = new ReflectionClass(ReflectionTest::class);

echo "Class name: " . $reflection->getName() . "\n";
echo "Is instantiable: " . ($reflection->isInstantiable() ? "Yes" : "No") . "\n";
echo "Number of properties: " . $reflection->getNumProperties() . "\n";
echo "Number of methods: " . $reflection->getNumMethods() . "\n";

// Get all properties
$properties = $reflection->getProperties();
echo "Properties:\n";
foreach ($properties as $prop) {
    echo "  - {$prop->getName()} ({$prop->getVisibility()})\n";
}

// Get all methods
$methods = $reflection->getMethods();
echo "Methods:\n";
foreach ($methods as $method) {
    echo "  - {$method->getName()} ({$method->getVisibility()})\n";
}

// Access private property via reflection
$privateProp = $reflection->getProperty('privateProp');
$privateProp->setAccessible(true);
echo "Private property value: " . $privateProp->getValue($reflectionTest) . "\n";

// ============================================================================
// Test 9: Dynamic Property Manipulation
// ============================================================================
echo "\n--- Test 9: Dynamic Property Manipulation ---\n";

class DynamicProperties {
    // Intentionally no property declarations
}

$dynamic = new DynamicProperties();

// Add dynamic properties
for ($i = 0; $i < 50; $i++) {
    $dynamic->{"property{$i}"} = "Value{$i}";
}

echo "Added 50 dynamic properties\n";

// Access dynamic properties
echo "First property: {$dynamic->property0}\n";
echo "Last property: {$dynamic->property49}\n";

// Check property exists
echo "Has property25: " . (isset($dynamic->property25) ? "Yes" : "No") . "\n";

// Unset property
unset($dynamic->property25);
echo "After unset, has property25: " . (isset($dynamic->property25) ? "Yes" : "No") . "\n";

// ============================================================================
// Test 10: Observer Pattern
// ============================================================================
echo "\n--- Test 10: Observer Pattern ---\n";

interface Observer {
    public function update(Subject $subject);
}

interface Subject {
    public function attach(Observer $observer);
    public function detach(Observer $observer);
    public function notify();
    public function getState();
    public function setState($state);
}

class ConcreteSubject implements Subject {
    private $observers = [];
    private $state;
    
    public function attach(Observer $observer) {
        $this->observers[] = $observer;
    }
    
    public function detach(Observer $observer) {
        $key = array_search($observer, $this->observers, true);
        if ($key !== false) {
            unset($this->observers[$key]);
        }
    }
    
    public function notify() {
        foreach ($this->observers as $observer) {
            $observer->update($this);
        }
    }
    
    public function getState() {
        return $this->state;
    }
    
    public function setState($state) {
        $this->state = $state;
        $this->notify();
    }
}

class ConcreteObserver implements Observer {
    private $id;
    private $lastState;
    
    public function __construct($id) {
        $this->id = $id;
    }
    
    public function update(Subject $subject) {
        $this->lastState = $subject->getState();
    }
    
    public function getLastState() {
        return $this->lastState;
    }
    
    public function getId() {
        return $this->id;
    }
}

$subject = new ConcreteSubject();

// Attach many observers
$observers = [];
for ($i = 0; $i < 20; $i++) {
    $observer = new ConcreteObserver($i);
    $subject->attach($observer);
    $observers[] = $observer;
}

echo "Attached 20 observers\n";

// Set state (triggers notifications)
$subject->setState("Initial State");

// Check observers received update
$firstObserver = $observers[0];
echo "Observer {$firstObserver->getId()} last state: {$firstObserver->getLastState()}\n";

// Detach some observers
for ($i = 0; $i < 10; $i++) {
    $subject->detach($observers[$i]);
}

echo "Detached 10 observers, remaining: " . count($observers) - 10 . "\n";

// ============================================================================
// Test 11: Dependency Injection Container
// ============================================================================
echo "\n--- Test 11: Dependency Injection Container ---\n";

class DIContainer {
    private $bindings = [];
    private $instances = [];
    
    public function bind($abstract, $concrete) {
        $this->bindings[$abstract] = $concrete;
    }
    
    public function singleton($abstract, $concrete) {
        $this->bindings[$abstract] = ['concrete' => $concrete, 'singleton' => true];
    }
    
    public function make($abstract) {
        if (isset($this->instances[$abstract])) {
            return $this->instances[$abstract];
        }
        
        if (isset($this->bindings[$abstract])) {
            $binding = $this->bindings[$abstract];
            if (is_array($binding) && isset($binding['singleton']) && $binding['singleton']) {
                $instance = $binding['concrete']($this);
                $this->instances[$abstract] = $instance;
                return $instance;
            }
            return $binding($this);
        }
        
        return new $abstract();
    }
}

class ServiceA {
    private $id;
    
    public function __construct() {
        $this->id = uniqid();
    }
    
    public function getId() {
        return $this->id;
    }
}

class ServiceB {
    private $serviceA;
    private $data;
    
    public function __construct(ServiceA $serviceA) {
        $this->serviceA = $serviceA;
        $this->data = [];
    }
    
    public function getServiceAId() {
        return $this->serviceA->getId();
    }
    
    public function addData($key, $value) {
        $this->data[$key] = $value;
    }
}

class ServiceC {
    private $serviceB;
    private $serviceA;
    
    public function __construct(ServiceB $serviceB, ServiceA $serviceA) {
        $this->serviceB = $serviceB;
        $this->serviceA = $serviceA;
    }
    
    public function getServiceBData() {
        return $this->serviceB;
    }
}

$container = new DIContainer();

// Bind services
$container->bind(ServiceA::class, function($c) {
    return new ServiceA();
});

$container->bind(ServiceB::class, function($c) {
    return new ServiceB($c->make(ServiceA::class));
});

$container->singleton(ServiceC::class, function($c) {
    return new ServiceC(
        $c->make(ServiceB::class),
        $c->make(ServiceA::class)
    );
});

// Create instances
$serviceC1 = $container->make(ServiceC::class);
$serviceC2 = $container->make(ServiceC::class);

echo "ServiceC singleton check: " . ($serviceC1 === $serviceC2 ? "Same instance" : "Different instances") . "\n";

// ============================================================================
// Test 12: Object Pool
// ============================================================================
echo "\n--- Test 12: Object Pool ---\n";

class ObjectPool {
    private $pool = [];
    private $maxSize;
    
    public function __construct($maxSize = 100) {
        $this->maxSize = $maxSize;
    }
    
    public function acquire() {
        if (count($this->pool) > 0) {
            return array_pop($this->pool);
        }
        return new PoolableObject();
    }
    
    public function release($object) {
        if (count($this->pool) < $this->maxSize) {
            $object->reset();
            $this->pool[] = $object;
            return true;
        }
        return false;
    }
    
    public function getPoolSize() {
        return count($this->pool);
    }
}

class PoolableObject {
    public $id;
    public $data = [];
    
    public function __construct() {
        $this->id = uniqid();
    }
    
    public function reset() {
        $this->data = [];
    }
    
    public function setData($data) {
        $this->data = $data;
    }
}

$pool = new ObjectPool(50);

// Acquire and release many objects
$acquired = [];
for ($i = 0; $i < 100; $i++) {
    $obj = $pool->acquire();
    $obj->setData(["index" => $i, "data" => str_repeat("x", 50)]);
    $acquired[] = $obj;
}

echo "Acquired 100 objects\n";
echo "Pool size: " . $pool->getPoolSize() . "\n";

// Release all
foreach ($acquired as $obj) {
    $pool->release($obj);
}

echo "Released all objects\n";
echo "Pool size: " . $pool->getPoolSize() . "\n";

// ============================================================================
// Test 13: Factory Pattern
// ============================================================================
echo "\n--- Test 13: Factory Pattern ---\n";

abstract class Vehicle {
    abstract public function getType();
}

class Car extends Vehicle {
    public function getType() { return "Car"; }
}

class Truck extends Vehicle {
    public function getType() { return "Truck"; }
}

class Motorcycle extends Vehicle {
    public function getType() { return "Motorcycle"; }
}

class Bicycle extends Vehicle {
    public function getType() { return "Bicycle"; }
}

class VehicleFactory {
    private $creators = [];
    
    public function registerCreator($type, $creator) {
        $this->creators[$type] = $creator;
    }
    
    public function create($type) {
        if (isset($this->creators[$type])) {
            return $this->creators[$type]();
        }
        
        return match($type) {
            'car' => new Car(),
            'truck' => new Truck(),
            'motorcycle' => new Motorcycle(),
            'bicycle' => new Bicycle(),
            default => null,
        };
    }
}

$factory = new VehicleFactory();

$factory->registerCreator('electric_car', function() {
    return new class extends Car {
        public function getType() { return "Electric Car"; }
    };
});

// Create many vehicles
$vehicles = [];
for ($i = 0; $i < 50; $i++) {
    $type = ['car', 'truck', 'motorcycle', 'bicycle', 'electric_car'][$i % 5];
    $vehicles[] = $factory->create($type);
}

echo "Created " . count($vehicles) . " vehicles\n";

// ============================================================================
// Test 14: Magic Methods
// ============================================================================
echo "\n--- Test 14: Magic Methods ---\n";

class MagicMethods {
    private $data = [];
    private $callHistory = [];
    
    public function __get($name) {
        $this->callHistory[] = "__get: {$name}";
        return $this->data[$name] ?? null;
    }
    
    public function __set($name, $value) {
        $this->callHistory[] = "__set: {$name}";
        $this->data[$name] = $value;
    }
    
    public function __isset($name) {
        return isset($this->data[$name]);
    }
    
    public function __unset($name) {
        $this->callHistory[] = "__unset: {$name}";
        unset($this->data[$name]);
    }
    
    public function __call($name, $args) {
        $this->callHistory[] = "__call: {$name}";
        return "Called {$name} with " . count($args) . " args";
    }
    
    public function __toString() {
        return "MagicMethods instance with " . count($this->data) . " properties";
    }
    
    public function getCallHistory() {
        return $this->callHistory;
    }
}

$magic = new MagicMethods();
$magic->property1 = "value1";
$magic->property2 = "value2";

echo $magic->property1 . "\n";
echo $magic->property3 . "\n"; // Returns null
echo $magic->undefinedMethod("arg1", "arg2") . "\n";
echo $magic . "\n";

echo "Magic methods called: " . count($magic->getCallHistory()) . " times\n";

// ============================================================================
// Test 15: ArrayAccess Implementation
// ============================================================================
echo "\n--- Test 15: ArrayAccess Implementation ---\n";

class ArrayAccessCollection implements ArrayAccess {
    private $data = [];
    
    public function offsetExists($offset): bool {
        return isset($this->data[$offset]);
    }
    
    public function offsetGet($offset): mixed {
        return $this->data[$offset] ?? null;
    }
    
    public function offsetSet($offset, $value): void {
        if ($offset === null) {
            $this->data[] = $value;
        } else {
            $this->data[$offset] = $value;
        }
    }
    
    public function offsetUnset($offset): void {
        unset($this->data[$offset]);
    }
}

$collection = new ArrayAccessCollection();

// Use array access
for ($i = 0; $i < 100; $i++) {
    $collection[] = new Item($i, "CollectionItem{$i}", $i * 100);
}

echo "Collection size: " . count($collection) . "\n";

// Access elements
echo "First item: " . $collection[0]->name . "\n";
echo "Last item: " . $collection[99]->name . "\n";

// ============================================================================
// Test 16: Iterator Implementation
// ============================================================================
echo "\n--- Test 16: Iterator Implementation ---\n";

class IteratorCollection implements Iterator {
    private $items = [];
    private $position = 0;
    
    public function __construct($count = 50) {
        for ($i = 0; $i < $count; $i++) {
            $this->items[] = new Item($i, "IterItem{$i}", $i);
        }
    }
    
    public function rewind(): void {
        $this->position = 0;
    }
    
    public function current(): mixed {
        return $this->items[$this->position];
    }
    
    public function key(): mixed {
        return $this->position;
    }
    
    public function next(): void {
        $this->position++;
    }
    
    public function valid(): bool {
        return isset($this->items[$this->position]);
    }
}

$iterator = new IteratorCollection(100);

echo "Iterating over collection:\n";
$count = 0;
foreach ($iterator as $key => $item) {
    if ($count < 3) {
        echo "  Key: {$key}, Item: {$item->name}\n";
    }
    $count++;
    if ($count >= 100) break;
}
echo "Total items iterated: {$count}\n";

// ============================================================================
// Test 17: Stringable Objects
// ============================================================================
echo "\n--- Test 17: Stringable Objects ---\n";

class Email implements Stringable {
    private $localPart;
    private $domain;
    
    public function __construct($email) {
        $parts = explode('@', $email);
        $this->localPart = $parts[0];
        $this->domain = $parts[1] ?? '';
    }
    
    public function getLocalPart() {
        return $this->localPart;
    }
    
    public function getDomain() {
        return $this->domain;
    }
    
    public function __toString(): string {
        return "{$this->localPart}@{$this->domain}";
    }
}

class Url implements Stringable {
    private $scheme;
    private $host;
    private $path;
    
    public function __construct($url) {
        $parts = parse_url($url);
        $this->scheme = $parts['scheme'] ?? '';
        $this->host = $parts['host'] ?? '';
        $this->path = $parts['path'] ?? '';
    }
    
    public function __toString(): string {
        $url = "{$this->scheme}://{$this->host}";
        if (!empty($this->path)) {
            $url .= $this->path;
        }
        return $url;
    }
}

$email = new Email("test@example.com");
$url = new Url("https://example.com/path/to/resource");

echo "Email: " . str($email) . "\n";
echo "URL: " . str($url) . "\n";

// ============================================================================
// Final Summary
// ============================================================================
echo "\n=== Test Suite Completed ===\n";
echo "All OOP scenarios tested:\n";
echo "1. Circular references - tested\n";
echo "2. Self-referencing objects - tested\n";
echo "3. Closures capturing objects - tested\n";
echo "4. Exception handling with objects - tested\n";
echo "5. Object arrays and iteration - tested\n";
echo "6. Static properties and singleton - tested\n";
echo "7. Object cloning - tested\n";
echo "8. Reflection operations - tested\n";
echo "9. Dynamic property manipulation - tested\n";
echo "10. Observer pattern - tested\n";
echo "11. Dependency injection container - tested\n";
echo "12. Object pool - tested\n";
echo "13. Factory pattern - tested\n";
echo "14. Magic methods - tested\n";
echo "15. ArrayAccess implementation - tested\n";
echo "16. Iterator implementation - tested\n";
echo "17. Stringable objects - tested\n";
echo "\nDone\n";
