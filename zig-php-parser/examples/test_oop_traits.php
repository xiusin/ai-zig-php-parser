<?php
// Traits testing
trait Logger {
    private $logs = [];
    
    public function log($message) {
        $this->logs[] = $message;
    }
    
    public function getLogs() {
        return $this->logs;
    }
    
    public function clearLogs() {
        $this->logs = [];
    }
}

trait Validator {
    public function validateEmail($email) {
        return filter_var($email, FILTER_VALIDATE_EMAIL) !== false;
    }
    
    public function validateLength($str, $min, $max) {
        $len = strlen($str);
        return $len >= $min && $len <= $max;
    }
}

trait Serializer {
    public function toArray() {
        $reflection = new ReflectionClass($this);
        $properties = [];
        foreach ($reflection->getProperties() as $property) {
            $property->setAccessible(true);
            $properties[$property->getName()] = $property->getValue($this);
        }
        return $properties;
    }
    
    public function toJson() {
        return json_encode($this->toArray());
    }
}

trait Cacheable {
    private $cache = [];
    private $cacheTime = [];
    
    public function cache($key, $value, $ttl = 3600) {
        $this->cache[$key] = $value;
        $this->cacheTime[$key] = time() + $ttl;
    }
    
    public function getCache($key) {
        if (!isset($this->cache[$key])) {
            return null;
        }
        
        if (time() > $this->cacheTime[$key]) {
            unset($this->cache[$key]);
            unset($this->cacheTime[$key]);
            return null;
        }
        
        return $this->cache[$key];
    }
    
    public function clearCache() {
        $this->cache = [];
        $this->cacheTime = [];
    }
}

// Use multiple traits
class UserProfile {
    use Logger, Validator, Serializer, Cacheable;
    
    private $username;
    private $email;
    private $age;
    
    public function __construct($username, $email, $age) {
        $this->username = $username;
        $this->email = $email;
        $this->age = $age;
    }
    
    public function validate() {
        $this->log("Validating user profile");
        
        if (!$this->validateLength($this->username, 3, 20)) {
            $this->log("Username length invalid");
            return false;
        }
        
        if (!$this->validateEmail($this->email)) {
            $this->log("Email invalid");
            return false;
        }
        
        if ($this->age < 18 || $this->age > 120) {
            $this->log("Age invalid");
            return false;
        }
        
        $this->log("Validation passed");
        return true;
    }
    
    public function getProfile() {
        $cacheKey = "profile_{$this->username}";
        $cached = $this->getCache($cacheKey);
        
        if ($cached !== null) {
            $this->log("Returning cached profile");
            return $cached;
        }
        
        $profile = $this->toArray();
        $this->cache($cacheKey, $profile, 300);
        return $profile;
    }
}

class Product {
    use Logger, Serializer, Cacheable;
    
    private $id;
    private $name;
    private $price;
    private $stock;
    
    public function __construct($id, $name, $price, $stock) {
        $this->id = $id;
        $this->name = $name;
        $this->price = $price;
        $this->stock = $stock;
    }
    
    public function decreaseStock($amount) {
        if ($this->stock < $amount) {
            $this->log("Insufficient stock for product {$this->id}");
            return false;
        }
        
        $this->stock -= $amount;
        $this->log("Decreased stock for product {$this->id} by {$amount}");
        $this->clearCache();
        return true;
    }
    
    public function increaseStock($amount) {
        $this->stock += $amount;
        $this->log("Increased stock for product {$this->id} by {$amount}");
        $this->clearCache();
    }
    
    public function isInStock() {
        return $this->stock > 0;
    }
}

// Test traits
$userProfile = new UserProfile("john_doe", "john@example.com", 30);

echo "=== User Profile Testing ===\n";
echo "Validation: " . ($userProfile->validate() ? "Passed" : "Failed") . "\n";
echo "Logs:\n";
foreach ($userProfile->getLogs() as $log) {
    echo "  {$log}\n";
}

echo "\nProfile array:\n";
print_r($userProfile->toArray());

echo "\nProfile JSON:\n";
echo $userProfile->toJson() . "\n";

echo "\nCached profile:\n";
print_r($userProfile->getProfile());

echo "\n=== Product Testing ===\n";
$product = new Product(1, "Laptop", 999.99, 10);

echo "Product in stock: " . ($product->isInStock() ? "Yes" : "No") . "\n";
echo "Decrease stock by 5: " . ($product->decreaseStock(5) ? "Success" : "Failed") . "\n";
echo "Product in stock: " . ($product->isInStock() ? "Yes" : "No") . "\n";
echo "Decrease stock by 10: " . ($product->decreaseStock(10) ? "Success" : "Failed") . "\n";

echo "\nProduct logs:\n";
foreach ($product->getLogs() as $log) {
    echo "  {$log}\n";
}

echo "\nDone\n";
