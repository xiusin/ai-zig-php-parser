<?php
// Serialization and cloning
class User {
    public $id;
    public $name;
    public $email;
    private $password;
    protected $role;
    
    public function __construct($id, $name, $email, $password, $role = 'user') {
        $this->id = $id;
        $this->name = $name;
        $this->email = $email;
        $this->password = $password;
        $this->role = $role;
    }
    
    public function __sleep() {
        return ['id', 'name', 'email'];
    }
    
    public function __wakeup() {
        $this->password = '***';
    }
    
    public function __clone() {
        $this->id = null;
    }
    
    public function getRole() {
        return $this->role;
    }
    
    public function setPassword($password) {
        $this->password = $password;
    }
}

class Session {
    private $data = [];
    private $timestamp;
    
    public function __construct() {
        $this->timestamp = time();
    }
    
    public function set($key, $value) {
        $this->data[$key] = $value;
    }
    
    public function get($key) {
        return $this->data[$key] ?? null;
    }
    
    public function getTimestamp() {
        return $this->timestamp;
    }
}

class Cache {
    private $items = [];
    private $ttl = 3600;
    
    public function __construct($ttl = 3600) {
        $this->ttl = $ttl;
    }
    
    public function set($key, $value, $ttl = null) {
        $this->items[$key] = [
            'value' => $value,
            'expires' => time() + ($ttl ?? $this->ttl)
        ];
    }
    
    public function get($key) {
        if (!isset($this->items[$key])) {
            return null;
        }
        
        if (time() > $this->items[$key]['expires']) {
            unset($this->items[$key]);
            return null;
        }
        
        return $this->items[$key]['value'];
    }
    
    public function clear() {
        $this->items = [];
    }
}

// Test serialization and cloning
echo "=== Serialization and Cloning Testing ===\n";

// Test __sleep and __wakeup
$user = new User(1, 'John Doe', 'john@example.com', 'secret123', 'admin');
echo "Original user: {$user->name} ({$user->email})\n";

$serialized = serialize($user);
echo "Serialized: " . substr($serialized, 0, 50) . "...\n";

$unserialized = unserialize($serialized);
echo "Unserialized: {$unserialized->name} ({$unserialized->email})\n";

// Test __clone
$cloned = clone $user;
echo "Cloned user ID: {$cloned->id} (should be null)\n";
echo "Cloned user name: {$cloned->name}\n";

// Test object comparison
echo "Same object? " . ($user === $cloned ? 'Yes' : 'No') . "\n";
echo "Equal values? " . ($user == $cloned ? 'Yes' : 'No') . "\n";

// Test session
$session = new Session();
$session->set('user_id', 1);
$session->set('logged_in', true);
echo "Session user_id: " . $session->get('user_id') . "\n";
echo "Session timestamp: " . $session->getTimestamp() . "\n";

// Test cache
$cache = new Cache(300);
$cache->set('key1', 'value1');
$cache->set('key2', 'value2', 600);

echo "Cache key1: " . $cache->get('key1') . "\n";
echo "Cache key2: " . $cache->get('key2') . "\n";
echo "Cache key3 (non-existent): " . ($cache->get('key3') ?? 'null') . "\n";

echo "\nDone\n";
