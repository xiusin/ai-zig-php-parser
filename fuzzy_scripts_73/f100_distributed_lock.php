<?php
// 分布式锁模拟：互斥/重入/租约
echo "=== Distributed Lock ===\n\n";

class Lock {
    public function __construct(
        public readonly string $key,
        public readonly string $owner,
        public readonly int $acquiredAt,
        public readonly int $ttl
    ) {}

    public function isExpired(int $now): bool {
        return $now > $this->acquiredAt + $this->ttl;
    }

    public function getRemainingTTL(int $now): int {
        return max(0, $this->acquiredAt + $this->ttl - $now);
    }
}

class DistributedLockManager {
    private array $locks = [];
    private array $waitQueue = [];
    private array $reentryCount = [];
    private array $lockHistory = [];
    private int $currentTime;

    public function __construct(int $startTime = 1000000) {
        $this->currentTime = $startTime;
    }

    public function tick(int $delta = 1): void {
        $this->currentTime += $delta;
        $this->cleanupExpired();
    }

    public function setTime(int $time): void {
        $this->currentTime = $time;
        $this->cleanupExpired();
    }

    public function tryAcquire(string $key, string $owner, int $ttl = 30): bool {
        $this->cleanupExpired();

        if (isset($this->locks[$key])) {
            $lock = $this->locks[$key];
            if ($lock->owner === $owner) {
                // 可重入
                $this->reentryCount[$key][$owner] = ($this->reentryCount[$key][$owner] ?? 0) + 1;
                $this->locks[$key] = new Lock($key, $owner, $this->currentTime, $ttl);
                $this->lockHistory[] = ['action' => 'reentry', 'key' => $key, 'owner' => $owner, 'time' => $this->currentTime];
                return true;
            }
            return false;
        }

        $this->locks[$key] = new Lock($key, $owner, $this->currentTime, $ttl);
        $this->reentryCount[$key][$owner] = 1;
        $this->lockHistory[] = ['action' => 'acquire', 'key' => $key, 'owner' => $owner, 'time' => $this->currentTime];
        return true;
    }

    public function acquire(string $key, string $owner, int $ttl = 30, int $timeout = 60): bool {
        $deadline = $this->currentTime + $timeout;

        while ($this->currentTime < $deadline) {
            if ($this->tryAcquire($key, $owner, $ttl)) {
                return true;
            }
            $this->tick(5);
        }
        return false;
    }

    public function release(string $key, string $owner): bool {
        if (!isset($this->locks[$key])) return false;
        if ($this->locks[$key]->owner !== $owner) return false;

        $count = $this->reentryCount[$key][$owner] ?? 1;
        if ($count > 1) {
            $this->reentryCount[$key][$owner] = $count - 1;
            $this->lockHistory[] = ['action' => 'release_reentry', 'key' => $key, 'owner' => $owner, 'time' => $this->currentTime];
        } else {
            unset($this->locks[$key]);
            unset($this->reentryCount[$key][$owner]);
            $this->lockHistory[] = ['action' => 'release', 'key' => $key, 'owner' => $owner, 'time' => $this->currentTime];
        }
        return true;
    }

    public function forceRelease(string $key): bool {
        if (!isset($this->locks[$key])) return false;
        $lock = $this->locks[$key];
        unset($this->locks[$key]);
        unset($this->reentryCount[$key][$lock->owner]);
        $this->lockHistory[] = ['action' => 'force_release', 'key' => $key, 'owner' => $lock->owner, 'time' => $this->currentTime];
        return true;
    }

    public function isLocked(string $key): bool {
        $this->cleanupExpired();
        return isset($this->locks[$key]);
    }

    public function getLockOwner(string $key): ?string {
        $this->cleanupExpired();
        return $this->locks[$key]->owner ?? null;
    }

    public function getRemainingTTL(string $key): int {
        if (!isset($this->locks[$key])) return 0;
        return $this->locks[$key]->getRemainingTTL($this->currentTime);
    }

    public function extend(string $key, string $owner, int $additionalTTL): bool {
        if (!isset($this->locks[$key])) return false;
        if ($this->locks[$key]->owner !== $owner) return false;

        $currentTTL = $this->locks[$key]->getRemainingTTL($this->currentTime);
        $newTTL = $currentTTL + $additionalTTL;
        $this->locks[$key] = new Lock($key, $owner, $this->currentTime, $newTTL);
        $this->lockHistory[] = ['action' => 'extend', 'key' => $key, 'owner' => $owner, 'time' => $this->currentTime, 'new_ttl' => $newTTL];
        return true;
    }

    private function cleanupExpired(): void {
        foreach ($this->locks as $key => $lock) {
            if ($lock->isExpired($this->currentTime)) {
                unset($this->locks[$key]);
                unset($this->reentryCount[$key][$lock->owner]);
                $this->lockHistory[] = ['action' => 'expired', 'key' => $key, 'owner' => $lock->owner, 'time' => $this->currentTime];
            }
        }
    }

    public function getActiveLocks(): array {
        $this->cleanupExpired();
        $result = [];
        foreach ($this->locks as $key => $lock) {
            $result[$key] = [
                'owner' => $lock->owner,
                'remaining_ttl' => $lock->getRemainingTTL($this->currentTime),
                'reentry_count' => $this->reentryCount[$key][$lock->owner] ?? 1,
            ];
        }
        return $result;
    }

    public function getLockCount(): int {
        $this->cleanupExpired();
        return count($this->locks);
    }

    public function getHistory(): array { return $this->lockHistory; }
    public function getCurrentTime(): int { return $this->currentTime; }
}

// === 测试 ===
$dlm = new DistributedLockManager(1000);

echo "--- Basic Lock/Unlock ---\n";
echo "Acquire 'resource_1' by Alice: " . ($dlm->tryAcquire('resource_1', 'Alice', 30) ? 'true' : 'false') . "\n";
echo "Is locked: " . ($dlm->isLocked('resource_1') ? 'true' : 'false') . "\n";
echo "Owner: " . $dlm->getLockOwner('resource_1') . "\n";
echo "Remaining TTL: " . $dlm->getRemainingTTL('resource_1') . "\n";

echo "\n--- Contention ---\n";
echo "Acquire by Bob (already locked): " . ($dlm->tryAcquire('resource_1', 'Bob', 30) ? 'true' : 'false') . "\n";
echo "Release by Bob (not owner): " . ($dlm->release('resource_1', 'Bob') ? 'true' : 'false') . "\n";
echo "Release by Alice: " . ($dlm->release('resource_1', 'Alice') ? 'true' : 'false') . "\n";
echo "Is locked: " . ($dlm->isLocked('resource_1') ? 'true' : 'false') . "\n";

echo "\n--- TTL Expiration ---\n";
$dlm->tryAcquire('resource_2', 'Charlie', 20);
echo "Acquire 'resource_2' by Charlie (TTL=20)\n";
echo "Current time: " . $dlm->getCurrentTime() . "\n";
echo "Remaining TTL: " . $dlm->getRemainingTTL('resource_2') . "\n";

$dlm->tick(10);
echo "After tick(10), time: " . $dlm->getCurrentTime() . ", TTL: " . $dlm->getRemainingTTL('resource_2') . "\n";

$dlm->tick(15);
echo "After tick(15), time: " . $dlm->getCurrentTime() . "\n";
echo "Is locked (expired): " . ($dlm->isLocked('resource_2') ? 'true' : 'false') . "\n";

echo "\n--- Lock Extension ---\n";
$dlm->tryAcquire('resource_3', 'Diana', 20);
echo "Acquire 'resource_3' by Diana (TTL=20)\n";
$dlm->tick(10);
echo "After tick(10), TTL: " . $dlm->getRemainingTTL('resource_3') . "\n";
$dlm->extend('resource_3', 'Diana', 30);
echo "After extend(30), TTL: " . $dlm->getRemainingTTL('resource_3') . "\n";
$dlm->tick(20);
echo "After tick(20), TTL: " . $dlm->getRemainingTTL('resource_3') . "\n";
echo "Is locked: " . ($dlm->isLocked('resource_3') ? 'true' : 'false') . "\n";

echo "\n--- Reentrant Lock ---\n";
$dlm->tryAcquire('resource_4', 'Eve', 50);
echo "First acquire by Eve: " . ($dlm->isLocked('resource_4') ? 'true' : 'false') . "\n";
$dlm->tryAcquire('resource_4', 'Eve', 50);
echo "Second acquire (reentrant): true\n";
$dlm->tryAcquire('resource_4', 'Eve', 50);
echo "Third acquire (reentrant): true\n";

$dlm->release('resource_4', 'Eve');
echo "First release (still locked): " . ($dlm->isLocked('resource_4') ? 'true' : 'false') . "\n";
$dlm->release('resource_4', 'Eve');
echo "Second release (still locked): " . ($dlm->isLocked('resource_4') ? 'true' : 'false') . "\n";
$dlm->release('resource_4', 'Eve');
echo "Third release (unlocked): " . ($dlm->isLocked('resource_4') ? 'true' : 'false') . "\n";

echo "\n--- Blocking Acquire (with timeout) ---\n";
$dlm->tryAcquire('shared_resource', 'Worker1', 30);
echo "Worker1 acquired shared_resource\n";
echo "Worker2 trying to acquire with timeout=60...\n";
// This will simulate waiting
$start = $dlm->getCurrentTime();
$result = $dlm->acquire('shared_resource', 'Worker2', 30, 60);
$elapsed = $dlm->getCurrentTime() - $start;
echo "Worker2 acquired: " . ($result ? 'true' : 'false') . " (waited ${elapsed}s)\n";

echo "\n--- Force Release ---\n";
$dlm->tryAcquire('stuck_resource', 'StuckProcess', 1000);
echo "StuckProcess acquired stuck_resource\n";
echo "Force release: " . ($dlm->forceRelease('stuck_resource') ? 'true' : 'false') . "\n";
echo "Is locked: " . ($dlm->isLocked('stuck_resource') ? 'true' : 'false') . "\n";

echo "\n--- Active Locks ---\n";
foreach ($dlm->getActiveLocks() as $key => $info) {
    echo "  $key: owner={$info['owner']}, ttl={$info['remaining_ttl']}, reentry={$info['reentry_count']}\n";
}
echo "Total active: " . $dlm->getLockCount() . "\n";

echo "\n--- Lock History ---\n";
foreach ($dlm->getHistory() as $entry) {
    $details = '';
    if (isset($entry['new_ttl'])) $details = " new_ttl={$entry['new_ttl']}";
    echo "  [{$entry['time']}] {$entry['action']}: key={$entry['key']} owner={$entry['owner']}$details\n";
}
