<?php
// 极度混搭: 连接池 + 心跳检测 + 健康检查 + 自动重连 + 负载均衡
echo "=== f060: Connection Pool + Heartbeat + Health + LoadBalance ===\n";

class Connection {
    private bool $alive = true;
    private int $lastUsed = 0;
    private int $useCount = 0;

    public function __construct(public readonly string $id) {}

    public function execute(string $query): string {
        if (!$this->alive) return "ERROR: Connection {$this->id} is dead";
        $this->lastUsed = microtime(true);
        $this->useCount++;
        return "OK[{$this->id}]: $query";
    }

    public function isAlive(): bool { return $this->alive; }
    public function kill(): void { $this->alive = false; }
    public function revive(): void { $this->alive = true; $this->useCount = 0; }
    public function getUseCount(): int { return $this->useCount; }
    public function getLastUsed(): int { return $this->lastUsed; }
}

class ConnectionPool {
    private array $pool = [];
    private array $inUse = [];
    private int $roundRobin = 0;
    private array $healthLog = [];

    public function __construct(
        private int $minSize = 2,
        private int $maxSize = 5,
        private int $idleTimeout = 30
    ) {
        for ($i = 0; $i < $minSize; $i++) {
            $conn = new Connection("conn-$i");
            $this->pool[$conn->id] = $conn;
        }
    }

    public function acquire(): ?Connection {
        // 先从空闲池获取
        foreach ($this->pool as $conn) {
            if ($conn->isAlive()) {
                unset($this->pool[$conn->id]);
                $this->inUse[$conn->id] = $conn;
                return $conn;
            }
        }

        // 创建新连接
        if (count($this->pool) + count($this->inUse) < $this->maxSize) {
            $id = 'conn-' . (count($this->pool) + count($this->inUse));
            $conn = new Connection($id);
            $this->inUse[$conn->id] = $conn;
            $this->healthLog[] = "Created new connection: $id";
            return $conn;
        }

        return null; // 池满
    }

    public function release(Connection $conn): void {
        if (isset($this->inUse[$conn->id])) {
            unset($this->inUse[$conn->id]);
            if ($conn->isAlive()) {
                $this->pool[$conn->id] = $conn;
            }
        }
    }

    public function heartbeat(): array {
        $results = [];
        $allConns = array_merge($this->pool, $this->inUse);
        foreach ($allConns as $conn) {
            $status = $conn->isAlive() ? 'alive' : 'dead';
            $results[$conn->id] = $status;
            if (!$conn->isAlive()) {
                $this->healthLog[] = "Heartbeat: {$conn->id} is dead, attempting reconnect";
                $conn->revive();
                $this->healthLog[] = "Heartbeat: {$conn->id} reconnected";
            }
        }
        return $results;
    }

    public function roundRobinExecute(string $query): string {
        $allConns = array_values(array_filter(
            array_merge($this->pool, $this->inUse),
            fn($c) => $c->isAlive()
        ));
        if (empty($allConns)) return "ERROR: No available connections";
        $conn = $allConns[$this->roundRobin % count($allConns)];
        $this->roundRobin++;
        return $conn->execute($query);
    }

    public function stats(): array {
        return [
            'pool_size' => count($this->pool),
            'in_use' => count($this->inUse),
            'total' => count($this->pool) + count($this->inUse),
            'alive' => count(array_filter(array_merge($this->pool, $this->inUse), fn($c) => $c->isAlive())),
        ];
    }

    public function getHealthLog(): array { return $this->healthLog; }
}

// 测试
$pool = new ConnectionPool(2, 5);

echo "--- Initial State ---\n";
echo json_encode($pool->stats()) . "\n";

echo "\n--- Acquire & Execute ---\n";
$c1 = $pool->acquire();
$c2 = $pool->acquire();
echo $c1->execute("SELECT 1") . "\n";
echo $c2->execute("SELECT 2") . "\n";
echo $c1->execute("SELECT 3") . "\n";
echo json_encode($pool->stats()) . "\n";

echo "\n--- Release ---\n";
$pool->release($c1);
$pool->release($c2);
echo json_encode($pool->stats()) . "\n";

echo "\n--- Round Robin ---\n";
for ($i = 0; $i < 5; $i++) {
    echo $pool->roundRobinExecute("Query $i") . "\n";
}

echo "\n--- Connection Failure ---\n";
$c3 = $pool->acquire();
$c3->kill();
echo "Execute on dead: " . $c3->execute("SELECT 4") . "\n";
$pool->release($c3);

echo "\n--- Heartbeat ---\n";
$health = $pool->heartbeat();
echo "Health: " . json_encode($health) . "\n";

echo "\n--- Pool Exhaustion ---\n";
$conns = [];
for ($i = 0; $i < 5; $i++) {
    $conns[] = $pool->acquire();
}
echo json_encode($pool->stats()) . "\n";
$overflow = $pool->acquire();
echo "Overflow acquire: " . var_export($overflow, true) . "\n";

echo "\n--- Release All ---\n";
foreach ($conns as $c) $pool->release($c);
echo json_encode($pool->stats()) . "\n";

echo "\n--- Health Log ---\n";
foreach ($pool->getHealthLog() as $log) echo "  $log\n";

echo "=== f060 Done ===\n";
