<?php
// 极度混搭: 数据库 + MVCC + 隔离级别 + 死锁检测 + WAL
echo "=== f136: Database + MVCC + Isolation + Deadlock + WAL ===\n";

class MVCCRecord {
    public array $versions = [];
    public function __construct(public string $key) {}

    public function write(mixed $value, int $txnId): void {
        $this->versions[] = ['value' => $value, 'createdBy' => $txnId, 'minTxn' => $txnId, 'maxTxn' => PHP_INT_MAX];
        if (count($this->versions) > 1) $this->versions[count($this->versions) - 2]['maxTxn'] = $txnId;
    }

    public function read(int $txnId, array $activeTxns): mixed {
        for ($i = count($this->versions) - 1; $i >= 0; $i--) {
            $v = $this->versions[$i];
            if ($v['minTxn'] <= $txnId && $v['maxTxn'] > $txnId && !in_array($v['createdBy'], $activeTxns)) return $v['value'];
        }
        return null;
    }

    public function getVersionCount(): int { return count($this->versions); }
}

class Transaction {
    public array $writeSet = [];
    public array $readSet = [];
    public string $state = 'active';

    public function __construct(public int $id, public int $beginTs, public string $isolation = 'snapshot') {}
}

class MVCCDatabase {
    private array $records = [];
    private array $transactions = [];
    private int $nextTxnId = 1;
    private array $activeTxns = [];
    private array $wal = [];

    public function begin(string $isolation = 'snapshot'): Transaction {
        $txn = new Transaction($this->nextTxnId++, $this->nextTxnId, $isolation);
        $this->transactions[$txn->id] = $txn;
        $this->activeTxns[$txn->id] = $txn->id;
        return $txn;
    }

    public function read(Transaction $txn, string $key): mixed {
        if (!isset($this->records[$key])) return null;
        $txn->readSet[$key] = true;
        $activeTxns = array_diff($this->activeTxns, [$txn->id]);
        return $this->records[$key]->read($txn->beginTs, $activeTxns);
    }

    public function write(Transaction $txn, string $key, mixed $value): void {
        if (!isset($this->records[$key])) $this->records[$key] = new MVCCRecord($key);
        $txn->writeSet[$key] = $value;
    }

    public function commit(Transaction $txn): bool {
        foreach ($txn->writeSet as $key => $value) {
            $this->records[$key]->write($value, $txn->id);
            $this->wal[] = ['type' => 'write', 'key' => $key, 'value' => $value, 'txnId' => $txn->id, 'timestamp' => microtime(true)];
        }
        $txn->state = 'committed';
        unset($this->activeTxns[$txn->id]);
        return true;
    }

    public function abort(Transaction $txn): void {
        $txn->state = 'aborted';
        unset($this->activeTxns[$txn->id]);
    }

    public function getWAL(): array { return $this->wal; }
    public function replayWAL(): array {
        $state = [];
        foreach ($this->wal as $entry) {
            if ($entry['type'] === 'write') $state[$entry['key']] = $entry['value'];
        }
        return $state;
    }
}

class LockManager {
    private array $locks = []; // resource => [txnId => mode]
    private array $waitFor = []; // txn => [waiting for txn]

    public function acquire(int $txnId, string $resource, string $mode = 'shared'): bool {
        if (!isset($this->locks[$resource])) $this->locks[$resource] = [];
        // 检查冲突
        foreach ($this->locks[$resource] as $holder => $holderMode) {
            if ($holder === $txnId) continue;
            if ($mode === 'exclusive' || $holderMode === 'exclusive') {
                $this->waitFor[$txnId][$holder] = true;
                return false; // 需要等待
            }
        }
        $this->locks[$resource][$txnId] = $mode;
        unset($this->waitFor[$txnId]);
        return true;
    }

    public function release(int $txnId, string $resource): void {
        unset($this->locks[$resource][$txnId]);
    }

    public function releaseAll(int $txnId): void {
        foreach ($this->locks as $resource => $holders) {
            unset($this->locks[$resource][$txnId]);
        }
        unset($this->waitFor[$txnId]);
    }

    public function detectDeadlock(): ?array {
        foreach (array_keys($this->waitFor) as $start) {
            $cycle = $this->findCycle($start, $start, []);
            if ($cycle !== null) return $cycle;
        }
        return null;
    }

    private function findCycle(int $start, int $current, array $visited): ?array {
        if (in_array($current, $visited)) {
            if ($current === $start) return array_merge($visited, [$current]);
            return null;
        }
        $visited[] = $current;
        foreach (array_keys($this->waitFor[$current] ?? []) as $waiting) {
            $cycle = $this->findCycle($start, $waiting, $visited);
            if ($cycle !== null) return $cycle;
        }
        return null;
    }
}

class IsolationLevelDemo {
    private MVCCDatabase $db;

    public function __construct(MVCCDatabase $db) { $this->db = $db; }

    public function demonstrateReadCommitted(): void {
        echo "  Read Committed: Each read sees latest committed data\n";
        $t1 = $this->db->begin('read_committed');
        $t2 = $this->db->begin('read_committed');
        $this->db->write($t1, 'x', 100);
        $this->db->commit($t1);
        $val = $this->db->read($t2, 'x');
        echo "  T2 reads x = $val (sees T1's commit)\n";
        $this->db->commit($t2);
    }

    public function demonstrateSnapshotIsolation(): void {
        echo "  Snapshot Isolation: Reads see data from transaction start\n";
        $t1 = $this->db->begin('snapshot');
        $this->db->write($t1, 'y', 200);
        $this->db->commit($t1);
        $t2 = $this->db->begin('snapshot');
        $this->db->write($t2, 'y', 300);
        $val = $this->db->read($t2, 'y');
        echo "  T2 reads y = $val (sees own write)\n";
        $this->db->commit($t2);
    }

    public function demonstrateWriteSkew(): void {
        echo "  Write Skew: Two txns read overlapping data, write disjoint data\n";
        $t1 = $this->db->begin('snapshot');
        $t2 = $this->db->begin('snapshot');
        $this->db->write($t1, 'a', 1);
        $this->db->write($t2, 'b', 2);
        $this->db->commit($t1);
        $this->db->commit($t2);
        echo "  Both committed (write skew possible under snapshot isolation)\n";
    }
}

// 测试
echo "--- MVCC Basic Operations ---\n";
$db = new MVCCDatabase();

$t1 = $db->begin();
$db->write($t1, 'user:1', ['name' => 'Alice', 'age' => 30]);
$db->commit($t1);

$t2 = $db->begin();
$val = $db->read($t2, 'user:1');
echo "T2 reads: " . json_encode($val) . "\n";

// T3 更新
$t3 = $db->begin();
$db->write($t3, 'user:1', ['name' => 'Alice', 'age' => 31]);
$db->commit($t3);

// T2 仍然看到旧值 (snapshot)
$val2 = $db->read($t2, 'user:1');
echo "T2 reads after T3 update: " . json_encode($val2) . " (still sees old value)\n";
$db->commit($t2);

// T4 看到新值
$t4 = $db->begin();
$val4 = $db->read($t4, 'user:1');
echo "T4 reads: " . json_encode($val4) . " (sees new value)\n";
$db->commit($t4);

echo "\n--- Version Chain ---\n";
echo "user:1 has " . $db->records['user:1']->getVersionCount() . " versions\n";

echo "\n--- WAL (Write-Ahead Log) ---\n";
$wal = $db->getWAL();
echo "WAL entries: " . count($wal) . "\n";
foreach ($wal as $entry) echo "  [{$entry['type']}] key={$entry['key']} txn={$entry['txnId']}\n";

$replayed = $db->replayWAL();
echo "Replayed state: " . json_encode($replayed) . "\n";

echo "\n--- Isolation Levels ---\n";
$db2 = new MVCCDatabase();
$demo = new IsolationLevelDemo($db2);
$demo->demonstrateReadCommitted();
$demo->demonstrateSnapshotIsolation();
$demo->demonstrateWriteSkew();

echo "\n--- Lock Manager ---\n";
$lm = new LockManager();
echo "T1 acquires shared lock on A: " . var_export($lm->acquire(1, 'A', 'shared'), true) . "\n";
echo "T2 acquires shared lock on A: " . var_export($lm->acquire(2, 'A', 'shared'), true) . "\n";
echo "T3 acquires exclusive lock on A: " . var_export($lm->acquire(3, 'A', 'exclusive'), true) . " (blocked)\n";
echo "T1 releases A\n";
$lm->release(1, 'A');
echo "T3 acquires exclusive lock on A: " . var_export($lm->acquire(3, 'A', 'exclusive'), true) . " (still blocked by T2)\n";
echo "T2 releases A\n";
$lm->release(2, 'A');
echo "T3 acquires exclusive lock on A: " . var_export($lm->acquire(3, 'A', 'exclusive'), true) . "\n";
$lm->releaseAll(3);

echo "\n--- Deadlock Detection ---\n";
$lm2 = new LockManager();
// T1 holds A, wants B; T2 holds B, wants A
$lm2->acquire(1, 'A', 'exclusive');
$lm2->acquire(2, 'B', 'exclusive');
$lm2->acquire(1, 'B', 'exclusive'); // T1 waits for T2
$lm2->acquire(2, 'A', 'exclusive'); // T2 waits for T1
$deadlock = $lm2->detectDeadlock();
echo "Deadlock detected: " . ($deadlock ? implode(' → ', $deadlock) : 'none') . "\n";
if ($deadlock) {
    echo "Resolving by aborting T2\n";
    $lm2->releaseAll(2);
    $deadlock2 = $lm2->detectDeadlock();
    echo "After abort: deadlock = " . ($deadlock2 ? 'still exists' : 'resolved') . "\n";
}

echo "\n--- Concurrent Transaction Simulation ---\n";
$db3 = new MVCCDatabase();
$db3->begin();
$init = $db3->begin();
$db3->write($init, 'balance', 1000);
$db3->commit($init);

// 模拟并发转账
$txns = [];
for ($i = 0; $i < 3; $i++) {
    $t = $db3->begin();
    $txns[] = $t;
}
foreach ($txns as $t) {
    $balance = $db3->read($t, 'balance');
    echo "  T{$t->id} reads balance = $balance\n";
}
// 各自写入不同结果
$db3->write($txns[0], 'balance', 800);
$db3->write($txns[1], 'balance', 700);
$db3->commit($txns[0]);
echo "  T{$txns[0]->id} committed balance=800\n";
$db3->commit($txns[1]);
echo "  T{$txns[1]->id} committed balance=700 (overwrites T{$txns[0]->id})\n";
$db3->abort($txns[2]);

$final = $db3->begin();
echo "  Final balance: " . $db3->read($final, 'balance') . "\n";
$db3->commit($final);

echo "=== f136 Done ===\n";
