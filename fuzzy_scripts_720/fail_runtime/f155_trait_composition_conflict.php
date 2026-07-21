<?php
// Trait 深入：多重 Trait、冲突解决、抽象方法、属性、静态方法
echo "=== f155: Trait Composition + Conflict Resolution ===\n";

trait Trackable {
    protected array $trackingLog = [];
    protected float $startTime = 0;

    public function startTracking(): void {
        $this->startTime = microtime(true);
        $this->trackingLog[] = "Started at " . date('Y-m-d H:i:s');
    }

    public function stopTracking(): float {
        $elapsed = microtime(true) - $this->startTime;
        $this->trackingLog[] = sprintf("Stopped (elapsed: %.4fs)", $elapsed);
        return $elapsed;
    }

    public function getTrackingLog(): array {
        return $this->trackingLog;
    }
}

trait Loggable {
    protected array $logs = [];

    public function log(string $level, string $message): void {
        $this->logs[] = sprintf("[%s] %s: %s", date('H:i:s'), $level, $message);
    }

    public function getLogs(): array {
        return $this->logs;
    }

    public function clearLogs(): void {
        $this->logs = [];
    }

    abstract public function getLogPrefix(): string;
}

trait JsonSerializableTrait {
    public function toJson(): string {
        return json_encode($this->toArray());
    }

    public function fromJson(string $json): self {
        $data = json_decode($json, true);
        foreach ($data as $key => $value) {
            if (property_exists($this, $key)) {
                $this->$key = $value;
            }
        }
        return $this;
    }

    abstract public function toArray(): array;
}

trait Cacheable {
    private static array $cache = [];

    protected static function cacheGet(string $key): mixed {
        return self::$cache[$key] ?? null;
    }

    protected static function cacheSet(string $key, mixed $value, int $ttl = 3600): void {
        self::$cache[$key] = ['value' => $value, 'expires' => time() + $ttl];
    }

    protected static function cacheHas(string $key): bool {
        if (!isset(self::$cache[$key])) return false;
        if (self::$cache[$key]['expires'] < time()) {
            unset(self::$cache[$key]);
            return false;
        }
        return true;
    }

    public static function clearCache(): void {
        self::$cache = [];
    }
}

// Trait 冲突解决
trait A {
    public function hello(): string { return "Hello from A"; }
    public function world(): string { return "World from A"; }
}

trait B {
    public function hello(): string { return "Hello from B"; }
    public function universe(): string { return "Universe from B"; }
}

class Greeter {
    use A, B {
        A::hello insteadof B;
        B::hello as helloFromB;
    }
}

// 组合多个 Trait
class Task {
    use Trackable, Loggable, JsonSerializableTrait, Cacheable;

    public function __construct(
        public int $id,
        public string $title,
        public string $status = 'pending',
        public int $priority = 0,
    ) {}

    public function getLogPrefix(): string {
        return "Task#{$this->id}";
    }

    public function toArray(): array {
        return [
            'id' => $this->id,
            'title' => $this->title,
            'status' => $this->status,
            'priority' => $this->priority,
        ];
    }

    public function execute(): void {
        $this->startTracking();
        $this->log('INFO', "Executing task: {$this->title}");

        $this->status = 'running';
        $this->log('DEBUG', "Status changed to running");

        // 模拟工作
        $sum = 0;
        for ($i = 0; $i < 1000; $i++) $sum += $i;

        $this->status = 'completed';
        $this->log('INFO', "Task completed (sum=$sum)");

        $elapsed = $this->stopTracking();
        $this->log('INFO', sprintf("Execution time: %.4fs", $elapsed));
    }

    public static function findCached(int $id): ?self {
        $key = "task_$id";
        if (self::cacheHas($key)) {
            return self::cacheGet($key)['value'];
        }
        $task = new self($id, "Cached Task $id");
        self::cacheSet($key, $task);
        return $task;
    }
}

// 测试
echo "--- Trait Conflict Resolution ---\n";
$greeter = new Greeter();
echo "  A::hello: " . $greeter->hello() . "\n";
echo "  B::hello: " . $greeter->helloFromB() . "\n";
echo "  A::world: " . $greeter->world() . "\n";
echo "  B::universe: " . $greeter->universe() . "\n";

echo "\n--- Multi-Trait Composition ---\n";
$task = new Task(1, 'Compile PHP AOT', 'pending', 5);
echo "  Task: {$task->title} ({$task->status})\n";

$task->execute();
echo "\n  Logs:\n";
foreach ($task->getLogs() as $log) {
    echo "    $log\n";
}

echo "\n  Tracking:\n";
foreach ($task->getTrackingLog() as $entry) {
    echo "    $entry\n";
}

echo "\n--- Serialization via Trait ---\n";
$json = $task->toJson();
echo "  JSON: $json\n";
$task2 = new Task(0, '', '');
$task2->fromJson($json);
echo "  Restored: {$task2->title} ({$task2->status}, priority={$task2->priority})\n";

echo "\n--- Cacheable Trait ---\n";
Task::clearCache();
$t1 = Task::findCached(100);
$t2 = Task::findCached(100);
echo "  Same instance: " . ($t1 === $t2 ? 'YES' : 'NO') . "\n";
echo "  Task: {$t1->title}\n";

echo "\n--- Trait with Abstract Method ---\n";
$task3 = new Task(3, 'Test Task');
echo "  Prefix: " . $task3->getLogPrefix() . "\n";

echo "=== f155 Done ===\n";
