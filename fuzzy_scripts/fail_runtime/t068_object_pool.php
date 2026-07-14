<?php
// 对象池：管理可重用对象、acquire/release

class DatabaseConnection {
    private static int $nextId = 1;
    public int $id;
    public bool $inUse = false;
    public string $query = '';

    public function __construct() {
        $this->id = self::$nextId++;
    }

    public function execute(string $sql): string {
        $this->query = $sql;
        return "Result of: $sql";
    }

    public function reset(): void {
        $this->query = '';
        $this->inUse = false;
    }
}

class ObjectPool {
    private array $available = [];
    private array $inUse = [];
    private int $maxSize;

    public function __construct(int $maxSize = 5) {
        $this->maxSize = $maxSize;
        for ($i = 0; $i < $maxSize; $i++) {
            $this->available[] = new DatabaseConnection();
        }
    }

    public function acquire(): ?DatabaseConnection {
        if (count($this->available) > 0) {
            $conn = array_pop($this->available);
            $conn->inUse = true;
            $this->inUse[] = $conn;
            return $conn;
        }
        return null;
    }

    public function release(DatabaseConnection $conn): void {
        $conn->reset();
        $index = array_search($conn, $this->inUse, true);
        if ($index !== false) {
            array_splice($this->inUse, $index, 1);
        }
        $this->available[] = $conn;
    }

    public function availableCount(): int {
        return count($this->available);
    }

    public function inUseCount(): int {
        return count($this->inUse);
    }
}

// 创建对象池
$pool = new ObjectPool(5);
echo "pool_initial: available=" . $pool->availableCount() . ", inUse=" . $pool->inUseCount() . "\n";

// 获取连接
$conn1 = $pool->acquire();
$conn2 = $pool->acquire();
$conn3 = $pool->acquire();
echo "pool_after_acquire: available=" . $pool->availableCount() . ", inUse=" . $pool->inUseCount() . "\n";

// 执行查询
echo "query1: [" . $conn1->id . "] " . $conn1->execute("SELECT * FROM users") . "\n";
echo "query2: [" . $conn2->id . "] " . $conn2->execute("SELECT * FROM posts") . "\n";

// 释放连接
$pool->release($conn1);
echo "pool_after_release: available=" . $pool->availableCount() . ", inUse=" . $pool->inUseCount() . "\n";

// 重新获取
$conn4 = $pool->acquire();
echo "reacquire_id: " . $conn4->id . "\n";
echo "pool_reacquire: available=" . $pool->availableCount() . ", inUse=" . $pool->inUseCount() . "\n";

// 释放所有
$pool->release($conn2);
$pool->release($conn3);
$pool->release($conn4);
echo "pool_final: available=" . $pool->availableCount() . ", inUse=" . $pool->inUseCount() . "\n";

// 测试连接重用
$conn5 = $pool->acquire();
echo "reuse_check: " . ($conn5->query === '' ? 'true' : 'false') . "\n";
$pool->release($conn5);

// 测试并发获取（模拟）
$conns = [];
for ($i = 0; $i < 3; $i++) {
    $conns[] = $pool->acquire();
}
echo "concurrent: available=" . $pool->availableCount() . ", inUse=" . $pool->inUseCount() . "\n";
foreach ($conns as $c) {
    $pool->release($c);
}
echo "concurrent_release: available=" . $pool->availableCount() . "\n";
