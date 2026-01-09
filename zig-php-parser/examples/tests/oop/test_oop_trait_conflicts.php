<?php
// Trait conflicts and resolution
trait Loggable {
    public function log($message) {
        echo "[LOG] {$message}\n";
    }
}

trait Cacheable {
    public function log($message) {
        echo "[CACHE] {$message}\n";
    }
    
    public function cache($key, $value) {
        echo "Caching {$key}: {$value}\n";
    }
}

trait Timestampable {
    private $timestamp;
    
    public function setTimestamp() {
        $this->timestamp = time();
    }
    
    public function getTimestamp() {
        return $this->timestamp;
    }
}

trait Validatable {
    public function validate() {
        return true;
    }
}

trait Serializable {
    public function serialize() {
        return json_encode(get_object_vars($this));
    }
}

class Service {
    use Loggable, Timestampable;
    
    private $name;
    
    public function __construct($name) {
        $this->name = $name;
        $this->setTimestamp();
    }
    
    public function execute($task) {
        $this->log("Executing: {$task}");
        return "Done: {$task}";
    }
}

class DataStore {
    use Cacheable, Timestampable, Serializable;
    
    private $data = [];
    
    public function __construct() {
        $this->setTimestamp();
    }
    
    public function store($key, $value) {
        $this->data[$key] = $value;
        $this->cache($key, $value);
    }
    
    public function retrieve($key) {
        return $this->data[$key] ?? null;
    }
}

class MultiTraitClass {
    use Loggable, Cacheable {
        Cacheable::log insteadof Loggable;
    }
    
    use Timestampable, Validatable, Serializable;
    
    private $name;
    private $value;
    
    public function __construct($name, $value) {
        $this->name = $name;
        $this->value = $value;
        $this->setTimestamp();
    }
    
    public function process() {
        $this->log("Processing {$this->name}");
        $this->cache($this->name, $this->value);
        
        if ($this->validate()) {
            return $this->serialize();
        }
        
        return null;
    }
}

// Test trait conflicts
echo "=== Trait Conflicts Testing ===\n";

// Test Service
$service = new Service("MyService");
echo "Service execute: " . $service->execute("Task 1") . "\n";
echo "Service timestamp: " . $service->getTimestamp() . "\n\n";

// Test DataStore
$store = new DataStore();
$store->store("user_1", "John Doe");
echo "User 1: " . $store->retrieve("user_1") . "\n";
echo "Store timestamp: " . $store->getTimestamp() . "\n\n";

// Test MultiTraitClass
$multi = new MultiTraitClass("Test", "Value");
$result = $multi->process();
echo "MultiTrait result: " . $result . "\n";
echo "MultiTrait timestamp: " . $multi->getTimestamp() . "\n";

echo "\nDone\n";