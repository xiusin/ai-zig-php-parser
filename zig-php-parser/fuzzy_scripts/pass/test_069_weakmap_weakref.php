<?php
// 测试69: WeakMap和WeakReference - PHP 8.0弱引用特性
// 测试目的：验证弱引用不会阻止垃圾回收

class CacheEntry {
    public string $data;
    public int $timestamp;
    
    public function __construct(string $data) {
        $this->data = $data;
        $this->timestamp = time();
    }
}

// WeakMap: 以对象作为键，不阻止垃圾回收
class ObjectCache {
    private WeakMap $cache;
    
    public function __construct() {
        $this->cache = new WeakMap();
    }
    
    public function set(object $key, CacheEntry $value): void {
        $this->cache[$key] = $value;
    }
    
    public function get(object $key): ?CacheEntry {
        return $this->cache[$key] ?? null;
    }
    
    public function has(object $key): bool {
        return isset($this->cache[$key]);
    }
    
    public function count(): int {
        return count($this->cache);
    }
}

$cache = new ObjectCache();

// 创建对象并缓存
$obj1 = new stdClass();
$obj2 = new stdClass();
$obj3 = new stdClass();

$cache->set($obj1, new CacheEntry("Data for obj1"));
$cache->set($obj2, new CacheEntry("Data for obj2"));
$cache->set($obj3, new CacheEntry("Data for obj3"));

echo "Cache size: " . $cache->count() . "\n";
echo "obj1 data: " . $cache->get($obj1)->data . "\n";

// 删除对象引用
unset($obj2);
gc_collect_cycles();

echo "After removing obj2, cache size: " . $cache->count() . "\n";

// WeakReference: 单个对象的弱引用
class WeakCache {
    private array $references = [];
    
    public function set(string $key, object $object): void {
        $this->references[$key] = WeakReference::create($object);
    }
    
    public function get(string $key): ?object {
        $ref = $this->references[$key] ?? null;
        return $ref?->get();
    }
}

$weakCache = new WeakCache();
$tempObj = new class {
    public string $value = "temporary";
};

$weakCache->set('temp', $tempObj);
echo "\nWeak cache get: " . ($weakCache->get('temp')?->value ?? 'null') . "\n";

unset($tempObj);
gc_collect_cycles();

echo "After unset, weak cache get: " . ($weakCache->get('temp')?->value ?? 'null') . "\n";

// 实际应用：观察者模式不阻止被观察者释放
interface Observer {
    public function update(string $event): void;
}

class Subject {
    private WeakMap $observers;
    
    public function __construct() {
        $this->observers = new WeakMap();
    }
    
    public function attach(Observer $observer): void {
        $this->observers[$observer] = true;
    }
    
    public function notify(string $event): void {
        foreach ($this->observers as $observer => $_) {
            $observer->update($event);
        }
    }
    
    public function observerCount(): int {
        return count($this->observers);
    }
}

class ConcreteObserver implements Observer {
    private string $name;
    
    public function __construct(string $name) {
        $this->name = $name;
    }
    
    public function update(string $event): void {
        echo "Observer {$this->name} received: $event\n";
    }
}

$subject = new Subject();
$obs1 = new ConcreteObserver("A");
$obs2 = new ConcreteObserver("B");

$subject->attach($obs1);
$subject->attach($obs2);

echo "\nObserver count: " . $subject->observerCount() . "\n";
$subject->notify("Test event");

unset($obs1);
gc_collect_cycles();

echo "After removing obs1, count: " . $subject->observerCount() . "\n";
$subject->notify("Another event");
?>
