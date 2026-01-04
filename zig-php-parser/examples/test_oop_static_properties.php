<?php
// Static properties and methods
class Counter {
    private static $count = 0;
    private static $instances = [];
    private $id;
    
    public function __construct() {
        self::$count++;
        $this->id = self::$count;
        self::$instances[] = $this;
    }
    
    public function getId() {
        return $this->id;
    }
    
    public static function getCount() {
        return self::$count;
    }
    
    public static function reset() {
        self::$count = 0;
        self::$instances = [];
    }
    
    public static function getAllInstances() {
        return self::$instances;
    }
    
    public static function getInstance($id) {
        foreach (self::$instances as $instance) {
            if ($instance->getId() == $id) {
                return $instance;
            }
        }
        return null;
    }
    
    public static function createMultiple($count) {
        $instances = [];
        for ($i = 0; $i < $count; $i++) {
            $instances[] = new self();
        }
        return $instances;
    }
}

class Singleton {
    private static $instance = null;
    private $data = [];
    
    private function __construct() {
        echo "Creating Singleton instance\n";
    }
    
    public static function getInstance() {
        if (self::$instance === null) {
            self::$instance = new self();
        }
        return self::$instance;
    }
    
    public function setData($key, $value) {
        $this->data[$key] = $value;
    }
    
    public function getData($key) {
        return isset($this->data[$key]) ? $this->data[$key] : null;
    }
    
    private function __clone() {
        throw new Exception("Cannot clone singleton");
    }
    
    public function __wakeup() {
        throw new Exception("Cannot unserialize singleton");
    }
}

// Test static properties
echo "Creating counters...\n";
$counter1 = new Counter();
$counter2 = new Counter();
$counter3 = new Counter();

echo "Total count: " . Counter::getCount() . "\n";
echo "Counter 1 ID: " . $counter1->getId() . "\n";
echo "Counter 2 ID: " . $counter2->getId() . "\n";
echo "Counter 3 ID: " . $counter3->getId() . "\n";

$instances = Counter::createMultiple(5);
echo "After creating 5 more: " . Counter::getCount() . "\n";

$found = Counter::getInstance(3);
echo "Found instance with ID 3: " . ($found ? $found->getId() : "null") . "\n";

Counter::reset();
echo "After reset: " . Counter::getCount() . "\n";

// Test singleton
$singleton1 = Singleton::getInstance();
$singleton1->setData("key1", "value1");

$singleton2 = Singleton::getInstance();
echo "Singleton data: " . $singleton2->getData("key1") . "\n";
echo "Same instance: " . ($singleton1 === $singleton2 ? "yes" : "no") . "\n";

echo "Done\n";