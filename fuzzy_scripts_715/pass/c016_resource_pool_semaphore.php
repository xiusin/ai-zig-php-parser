<?php
// 极度混搭: 资源池化 + 连接管理 + 租约系统 + 信号量 + 异常回收
echo "=== c016: ResourcePool + Lease + Semaphore + Reclaim ===\n\n";

class PooledResource {
    private static int $nextId = 1;
    public readonly int $id;
    private bool $inUse = false;
    private float $createdAt;
    private ?float $leasedAt = null;
    private string $type;

    public function __construct(string $type) {
        $this->id = self::$nextId++;
        $this->type = $type;
        $this->createdAt = 0.0;
    }

    public function acquire(): void {
        $this->inUse = true;
        $this->leasedAt = 0.0;
    }

    public function release(): void {
        $this->inUse = false;
        $this->leasedAt = null;
    }

    public function isInUse(): bool {
        return $this->inUse;
    }

    public function getType(): string {
        return $this->type;
    }
}

class Semaphore {
    private int $permits;
    private int $available;
    private array $waitQueue = [];

    public function __construct(int $permits) {
        $this->permits = $permits;
        $this->available = $permits;
    }

    public function acquire(): bool {
        if ($this->available > 0) {
            $this->available--;
            return true;
        }
        $this->waitQueue[] = true;
        return false;
    }

    public function release(): void {
        if (!empty($this->waitQueue)) {
            array_shift($this->waitQueue);
        } else {
            $this->available++;
            if ($this->available > $this->permits) {
                $this->available = $this->permits;
            }
        }
    }

    public function availablePermits(): int {
        return $this->available;
    }

    public function waitingCount(): int {
        return count($this->waitQueue);
    }
}

class ResourcePool {
    private array $pool = [];
    private array $available = [];
    private array $inUse = [];
    private Semaphore $semaphore;
    private int $maxSize;
    private int $created = 0;
    private string $resourceType;
    private array $leaseHistory = [];

    public function __construct(string $type, int $maxSize = 5) {
        $this->resourceType = $type;
        $this->maxSize = $maxSize;
        $this->semaphore = new Semaphore($maxSize);
    }

    public function acquire(): PooledResource {
        if (!$this->semaphore->acquire()) {
            throw new RuntimeException("Pool exhausted: {$this->resourceType}");
        }

        if (!empty($this->available)) {
            $resource = array_pop($this->available);
        } elseif ($this->created < $this->maxSize) {
            $resource = new PooledResource($this->resourceType);
            $this->created++;
        } else {
            $this->semaphore->release();
            throw new RuntimeException("No resources available");
        }

        $resource->acquire();
        $this->inUse[$resource->id] = $resource;
        $this->leaseHistory[] = ['action' => 'acquire', 'id' => $resource->id];
        return $resource;
    }

    public function release(PooledResource $resource): void {
        if (!isset($this->inUse[$resource->id])) {
            throw new InvalidArgumentException("Resource {$resource->id} not in use");
        }

        $resource->release();
        unset($this->inUse[$resource->id]);
        $this->available[] = $resource;
        $this->semaphore->release();
        $this->leaseHistory[] = ['action' => 'release', 'id' => $resource->id];
    }

    public function getStats(): array {
        return [
            'type' => $this->resourceType,
            'maxSize' => $this->maxSize,
            'created' => $this->created,
            'available' => count($this->available),
            'inUse' => count($this->inUse),
            'permits' => $this->semaphore->availablePermits(),
            'waiting' => $this->semaphore->waitingCount(),
            'totalOps' => count($this->leaseHistory),
        ];
    }

    public function getHistory(): array {
        return $this->leaseHistory;
    }

    public function reclaimAll(): void {
        foreach ($this->inUse as $id => $resource) {
            $resource->release();
            $this->available[] = $resource;
            unset($this->inUse[$id]);
            $this->semaphore->release();
            $this->leaseHistory[] = ['action' => 'reclaim', 'id' => $id];
        }
    }
}

// === 测试 ===

echo "--- Pool Creation ---\n";
$pool = new ResourcePool('DBConnection', 3);
echo "Stats: " . json_encode($pool->getStats()) . "\n";

echo "\n--- Acquire/Release ---\n";
$r1 = $pool->acquire();
echo "Acquired #{$r1->id}\n";
$r2 = $pool->acquire();
echo "Acquired #{$r2->id}\n";
$r3 = $pool->acquire();
echo "Acquired #{$r3->id}\n";
echo "Stats: " . json_encode($pool->getStats()) . "\n";

echo "\n--- Pool Exhaustion ---\n";
try {
    $r4 = $pool->acquire();
    echo "Acquired #{$r4->id}\n";
} catch (RuntimeException $e) {
    echo "Expected error: " . $e->getMessage() . "\n";
}
echo "Stats: " . json_encode($pool->getStats()) . "\n";

echo "\n--- Release and Re-acquire ---\n";
$pool->release($r2);
echo "Released #{$r2->id}\n";
echo "Stats: " . json_encode($pool->getStats()) . "\n";

$r4 = $pool->acquire();
echo "Acquired #{$r4->id} (should reuse #{$r2->id})\n";
echo "Stats: " . json_encode($pool->getStats()) . "\n";

echo "\n--- Reclaim All ---\n";
$pool->reclaimAll();
echo "Stats: " . json_encode($pool->getStats()) . "\n";

echo "\n--- History ---\n";
$hist = $pool->getHistory();
foreach ($hist as $h) {
    echo "  {$h['action']} #{$h['id']}\n";
}

echo "\n--- Multiple Pools ---\n";
$dbPool = new ResourcePool('DB', 5);
$redisPool = new ResourcePool('Redis', 10);
$httpPool = new ResourcePool('HTTP', 3);

$resources = [];
$resources[] = $dbPool->acquire();
$resources[] = $dbPool->acquire();
$resources[] = $redisPool->acquire();
$resources[] = $httpPool->acquire();

echo "DB pool: " . json_encode($dbPool->getStats()) . "\n";
echo "Redis pool: " . json_encode($redisPool->getStats()) . "\n";
echo "HTTP pool: " . json_encode($httpPool->getStats()) . "\n";

// Release all
$dbPool->reclaimAll();
$redisPool->reclaimAll();
$httpPool->reclaimAll();

echo "\nAfter reclaim:\n";
echo "DB pool: " . json_encode($dbPool->getStats()) . "\n";
echo "Redis pool: " . json_encode($redisPool->getStats()) . "\n";
echo "HTTP pool: " . json_encode($httpPool->getStats()) . "\n";

echo "\n=== c016 Done ===\n";
