<?php
// 极度混搭: 数据库事务 + 隔离级别模拟 + MVCC + 死锁检测
echo "=== f080: DB Transaction + Isolation + MVCC + Deadlock ===\n";

class MVCCRecord {
    public array $versions = [];

    public function __construct(public string $key, mixed $value, int $ts) {
        $this->versions[] = ['value' => $value, 'ts' => $ts, 'deleted' => false];
    }

    public function write(mixed $value, int $ts): void {
        $this->versions[] = ['value' => $value, 'ts' => $ts, 'deleted' => false];
    }

    public function delete(int $ts): void {
        $this->versions[] = ['value' => null, 'ts' => $ts, 'deleted' => true];
    }

    public function read(int $ts): ?array {
        $result = null;
        foreach ($this->versions as $v) {
            if ($v['ts'] <= $ts) $result = $v;
        }
        return $result;
    }

    public function getVersionCount(): int { return count($this->versions); }
}

class MVCCStore {
    private array $records = [];
    private int $timestamp = 0;
    private array $transactions = [];
    private array $lockTable = [];
    private array $deadlockLog = [];

    public function begin(): int {
        $ts = ++$this->timestamp;
        $this->transactions[$ts] = ['status' => 'active', 'start_ts' => $ts, 'ops' => []];
        return $ts;
    }

    public function read(int $txId, string $key): mixed {
        if (!isset($this->records[$key])) return null;
        $version = $this->records[$key]->read($this->transactions[$txId]['start_ts']);
        if ($version === null || $version['deleted']) return null;
        $this->transactions[$txId]['ops'][] = "read $key = " . json_encode($version['value']);
        return $version['value'];
    }

    public function write(int $txId, string $key, mixed $value): bool {
        if (!$this->acquireLock($txId, $key)) return false;
        $commitTs = ++$this->timestamp;
        if (!isset($this->records[$key])) {
            $this->records[$key] = new MVCCRecord($key, $value, $commitTs);
        } else {
            $this->records[$key]->write($value, $commitTs);
        }
        $this->transactions[$txId]['ops'][] = "write $key = " . json_encode($value);
        return true;
    }

    public function delete(int $txId, string $key): bool {
        if (!$this->acquireLock($txId, $key)) return false;
        if (!isset($this->records[$key])) return false;
        $commitTs = ++$this->timestamp;
        $this->records[$key]->delete($commitTs);
        $this->transactions[$txId]['ops'][] = "delete $key";
        return true;
    }

    public function commit(int $txId): void {
        $this->transactions[$txId]['status'] = 'committed';
        $this->releaseLocks($txId);
    }

    public function rollback(int $txId): void {
        $this->transactions[$txId]['status'] = 'rolled_back';
        $this->releaseLocks($txId);
    }

    private function acquireLock(int $txId, string $key): bool {
        if (isset($this->lockTable[$key])) {
            if ($this->lockTable[$key] === $txId) return true;
            // 检测死锁
            $holder = $this->lockTable[$key];
            if ($this->waitForLock($txId, $holder)) {
                $this->deadlockLog[] = "Deadlock: T$txId waiting for T$holder on $key";
                return false;
            }
            return false;
        }
        $this->lockTable[$key] = $txId;
        return true;
    }

    private function waitForLock(int $waiter, int $holder): bool {
        foreach ($this->lockTable as $key => $owner) {
            if ($owner === $waiter) return true;
        }
        return false;
    }

    private function releaseLocks(int $txId): void {
        foreach ($this->lockTable as $key => $owner) {
            if ($owner === $txId) unset($this->lockTable[$key]);
        }
    }

    public function getRecordVersions(string $key): int {
        return $this->records[$key]->getVersionCount() ?? 0;
    }

    public function getTransactionLog(): array { return $this->transactions; }
    public function getDeadlockLog(): array { return $this->deadlockLog; }
}

// 测试
echo "--- Basic Transaction ---\n";
$db = new MVCCStore();
$tx1 = $db->begin();
$db->write($tx1, 'user:1', ['name' => 'Alice', 'balance' => 100]);
$db->write($tx1, 'user:2', ['name' => 'Bob', 'balance' => 50]);
$db->commit($tx1);

$tx2 = $db->begin();
echo "Read user:1: " . json_encode($db->read($tx2, 'user:1')) . "\n";
echo "Read user:2: " . json_encode($db->read($tx2, 'user:2')) . "\n";
$db->commit($tx2);

echo "\n--- MVCC Versioning ---\n";
$tx3 = $db->begin();
$db->write($tx3, 'user:1', ['name' => 'Alice', 'balance' => 150]);
$db->commit($tx3);
echo "Versions for user:1: " . $db->getRecordVersions('user:1') . "\n";

$tx4 = $db->begin();
echo "Current user:1: " . json_encode($db->read($tx4, 'user:1')) . "\n";
$db->commit($tx4);

echo "\n--- Transfer (Atomic) ---\n";
$tx5 = $db->begin();
$alice = $db->read($tx5, 'user:1');
$bob = $db->read($tx5, 'user:2');
echo "Before: Alice={$alice['balance']} Bob={$bob['balance']}\n";
$alice['balance'] -= 30;
$bob['balance'] += 30;
$db->write($tx5, 'user:1', $alice);
$db->write($tx5, 'user:2', $bob);
$db->commit($tx5);

$tx6 = $db->begin();
$aliceAfter = $db->read($tx6, 'user:1');
$bobAfter = $db->read($tx6, 'user:2');
echo "After transfer 30: Alice={$aliceAfter['balance']} Bob={$bobAfter['balance']}\n";
$db->commit($tx6);

echo "\n--- Rollback ---\n";
$tx7 = $db->begin();
$alice = $db->read($tx7, 'user:1');
$alice['balance'] -= 1000;
$db->write($tx7, 'user:1', $alice);
echo "Before rollback: " . $db->read($tx7, 'user:1')['balance'] . "\n";
$db->rollback($tx7);

$tx8 = $db->begin();
echo "After rollback: " . $db->read($tx8, 'user:1')['balance'] . "\n";
$db->commit($tx8);

echo "\n--- Delete ---\n";
$tx9 = $db->begin();
$db->delete($tx9, 'user:2');
$db->commit($tx9);
$tx10 = $db->begin();
echo "user:2 after delete: " . var_export($db->read($tx10, 'user:2'), true) . "\n";
$db->commit($tx10);

echo "\n--- Transaction Log ---\n";
foreach ($db->getTransactionLog() as $txId => $info) {
    echo "  T$txId: {$info['status']} (" . count($info['ops']) . " ops)\n";
}

echo "\n--- Deadlock Detection ---\n";
if (!empty($db->getDeadlockLog())) {
    echo "Deadlocks:\n";
    foreach ($db->getDeadlockLog() as $log) echo "  $log\n";
} else {
    echo "No deadlocks detected\n";
}

echo "=== f080 Done ===\n";
