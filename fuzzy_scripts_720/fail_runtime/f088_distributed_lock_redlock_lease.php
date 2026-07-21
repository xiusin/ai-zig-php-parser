<?php
// 极度混搭: 分布式锁 + RedLock算法 + 租约 + 续约 + 故障恢复
echo "=== f088: Distributed Lock + RedLock + Lease ===\n";

class LockNode {
    private array $locks = [];
    private array $leases = [];

    public function acquire(string $key, string $owner, int $ttl): bool {
        $now = microtime(true);
        if (isset($this->locks[$key]) && $this->locks[$key]['expire'] > $now) return false;
        $this->locks[$key] = ['owner' => $owner, 'expire' => $now + $ttl, 'ttl' => $ttl];
        $this->leases[$key] = ['owner' => $owner, 'acquired' => $now, 'renewals' => 0];
        return true;
    }

    public function release(string $key, string $owner): bool {
        if (!isset($this->locks[$key]) || $this->locks[$key]['owner'] !== $owner) return false;
        unset($this->locks[$key], $this->leases[$key]);
        return true;
    }

    public function renew(string $key, string $owner, int $ttl): bool {
        if (!isset($this->locks[$key]) || $this->locks[$key]['owner'] !== $owner) return false;
        $this->locks[$key]['expire'] = microtime(true) + $ttl;
        $this->leases[$key]['renewals']++;
        return true;
    }

    public function isLocked(string $key): bool {
        $now = microtime(true);
        return isset($this->locks[$key]) && $this->locks[$key]['expire'] > $now;
    }

    public function getOwner(string $key): ?string {
        return $this->locks[$key]['owner'] ?? null;
    }

    public function cleanup(): int {
        $now = microtime(true); $count = 0;
        foreach ($this->locks as $key => $lock) {
            if ($lock['expire'] <= $now) { unset($this->locks[$key], $this->leases[$key]); $count++; }
        }
        return $count;
    }

    public function getLeaseInfo(string $key): ?array { return $this->leases[$key] ?? null; }
}

class RedLock {
    private array $nodes;
    private float $retryDelay;
    private int $retryCount;
    private float $clockDriftFactor;

    public function __construct(array $nodes, float $retryDelay = 0.1, int $retryCount = 3, float $clockDriftFactor = 0.01) {
        $this->nodes = $nodes;
        $this->retryDelay = $retryDelay;
        $this->retryCount = $retryCount;
        $this->clockDriftFactor = $clockDriftFactor;
    }

    public function lock(string $resource, int $ttl, string $owner): ?array {
        $quorum = (int)(count($this->nodes) / 2) + 1;
        $startTime = microtime(true);

        for ($attempt = 0; $attempt < $this->retryCount; $attempt++) {
            $successCount = 0;
            foreach ($this->nodes as $node) {
                if ($node->acquire($resource, $owner, $ttl)) $successCount++;
            }
            $elapsed = (microtime(true) - $startTime) * 1000;
            $drift = $ttl * $this->clockDriftFactor + 2;
            $validityTime = $ttl - $elapsed - $drift;

            if ($successCount >= $quorum && $validityTime > 0) {
                return ['owner' => $owner, 'validity' => $validityTime, 'acquired' => $successCount];
            }
            // 失败，释放已获取的锁
            foreach ($this->nodes as $node) $node->release($resource, $owner);
            usleep((int)($this->retryDelay * 1000000 * (mt_rand(0, 100) / 100)));
        }
        return null;
    }

    public function unlock(string $resource, string $owner): int {
        $released = 0;
        foreach ($this->nodes as $node) {
            if ($node->release($resource, $owner)) $released++;
        }
        return $released;
    }
}

// 测试
echo "--- Single Node Lock ---\n";
$node = new LockNode();
echo "Acquire 'task1' by Alice: " . var_export($node->acquire('task1', 'alice', 2), true) . "\n";
echo "Acquire 'task1' by Bob: " . var_export($node->acquire('task1', 'bob', 2), true) . "\n";
echo "Is locked: " . var_export($node->isLocked('task1'), true) . "\n";
echo "Owner: " . $node->getOwner('task1') . "\n";
echo "Renew by Alice: " . var_export($node->renew('task1', 'alice', 5), true) . "\n";
echo "Renew by Bob: " . var_export($node->renew('task1', 'bob', 5), true) . "\n";
echo "Release by Bob: " . var_export($node->release('task1', 'bob'), true) . "\n";
echo "Release by Alice: " . var_export($node->release('task1', 'alice'), true) . "\n";
echo "Is locked after release: " . var_export($node->isLocked('task1'), true) . "\n";

echo "\n--- TTL Expiration ---\n";
$node2 = new LockNode();
$node2->acquire('task2', 'alice', 1);
echo "Is locked (immediate): " . var_export($node2->isLocked('task2'), true) . "\n";
sleep(2);
echo "Is locked (after TTL): " . var_export($node2->isLocked('task2'), true) . "\n";
echo "Cleanup: " . $node2->cleanup() . " expired locks removed\n";

echo "\n--- RedLock (3 nodes) ---\n";
$nodes = [new LockNode(), new LockNode(), new LockNode()];
$redlock = new RedLock($nodes, 0.05, 3);

echo "Lock 'resource1':\n";
$lock = $redlock->lock('resource1', 10, 'client-1');
echo "  Result: " . json_encode($lock) . "\n";

echo "\nLock 'resource1' by another client:\n";
$lock2 = $redlock->lock('resource1', 10, 'client-2');
echo "  Result: " . json_encode($lock2) . "\n";

echo "\nUnlock by client-1:\n";
$released = $redlock->unlock('resource1', 'client-1');
echo "  Released on $released nodes\n";

echo "\nLock 'resource1' by client-2 again:\n";
$lock3 = $redlock->lock('resource1', 10, 'client-2');
echo "  Result: " . json_encode($lock3) . "\n";

echo "\n--- Lease Info ---\n";
$node3 = new LockNode();
$node3->acquire('task3', 'alice', 10);
$node3->renew('task3', 'alice', 10);
$node3->renew('task3', 'alice', 10);
$lease = $node3->getLeaseInfo('task3');
echo "Lease: " . json_encode($lease) . "\n";

echo "\n--- 5-Node RedLock with Fault ---\n";
$nodes5 = [new LockNode(), new LockNode(), new LockNode(), new LockNode(), new LockNode()];
$redlock5 = new RedLock($nodes5, 0.05, 3);

$lock = $redlock5->lock('shared', 10, 'app-1');
echo "Lock on 5 nodes: " . json_encode($lock) . "\n";

// 模拟部分节点故障 - 手动释放其中2个
$nodes5[1]->release('shared', 'app-1');
$nodes5[3]->release('shared', 'app-1');

$lock2 = $redlock5->lock('shared', 10, 'app-2');
echo "Lock attempt with 2 nodes down: " . json_encode($lock2) . "\n";

echo "=== f088 Done ===\n";
