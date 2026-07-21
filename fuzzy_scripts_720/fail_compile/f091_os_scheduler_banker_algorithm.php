<?php
// 极度混搭: 操作系统调度模拟 + 进程状态 + 资源分配 + 银行家算法
echo "=== f091: OS Scheduler + Process + Banker ===\n";

class Process {
    public string $state = 'ready';
    public int $waitingTime = 0;
    public int $completionTime = 0;

    public function __construct(
        public int $pid,
        public string $name,
        public int $burstTime,
        public int $arrivalTime = 0,
        public int $priority = 0,
        public array $maxResources = [],
        public array $allocated = []
    ) {}

    public function remainingNeed(): array {
        $need = [];
        foreach ($this->maxResources as $r => $max) {
            $need[$r] = $max - ($this->allocated[$r] ?? 0);
        }
        return $need;
    }
}

class OSScheduler {
    public static function fcfs(array $processes): array {
        usort($processes, fn($a, $b) => $a->arrivalTime <=> $b->arrivalTime);
        $currentTime = 0;
        $results = [];
        foreach ($processes as $p) {
            if ($currentTime < $p->arrivalTime) $currentTime = $p->arrivalTime;
            $p->waitingTime = $currentTime - $p->arrivalTime;
            $currentTime += $p->burstTime;
            $p->completionTime = $currentTime;
            $results[] = $p;
        }
        return $results;
    }

    public static function sjf(array $processes): array {
        $completed = []; $ready = []; $currentTime = 0;
        $pending = $processes;
        while (!empty($pending) || !empty($ready)) {
            foreach ($pending as $i => $p) {
                if ($p->arrivalTime <= $currentTime) { $ready[] = $p; unset($pending[$i]); }
            }
            $pending = array_values($pending);
            if (empty($ready)) { $currentTime = min(array_map(fn($p) => $p->arrivalTime, $pending)); continue; }
            usort($ready, fn($a, $b) => $a->burstTime <=> $b->burstTime);
            $p = array_shift($ready);
            $p->waitingTime = $currentTime - $p->arrivalTime;
            $currentTime += $p->burstTime;
            $p->completionTime = $currentTime;
            $completed[] = $p;
        }
        return $completed;
    }

    public static function roundRobin(array $processes, int $quantum = 2): array {
        $queue = []; $completed = []; $currentTime = 0;
        $pending = $processes;
        $remaining = array_combine(array_map(fn($p) => $p->pid, $processes), array_map(fn($p) => $p->burstTime, $processes));

        while (!empty($pending) || !empty($queue)) {
            foreach ($pending as $i => $p) {
                if ($p->arrivalTime <= $currentTime) { $queue[] = $p; unset($pending[$i]); }
            }
            $pending = array_values($pending);
            if (empty($queue)) { $currentTime = min(array_map(fn($p) => $p->arrivalTime, $pending)); continue; }
            $p = array_shift($queue);
            $exec = min($quantum, $remaining[$p->pid]);
            $remaining[$p->pid] -= $exec;
            $currentTime += $exec;
            foreach ($pending as $i => $np) {
                if ($np->arrivalTime <= $currentTime) { $queue[] = $np; unset($pending[$i]); }
            }
            $pending = array_values($pending);
            if ($remaining[$p->pid] > 0) { $queue[] = $p; }
            else { $p->completionTime = $currentTime; $p->waitingTime = $currentTime - $p->arrivalTime - $p->burstTime; $completed[] = $p; }
        }
        return $completed;
    }

    public static function priority(array $processes): array {
        usort($processes, fn($a, $b) => $a->priority <=> $b->priority ?: $a->arrivalTime <=> $b->arrivalTime);
        $currentTime = 0;
        foreach ($processes as $p) {
            if ($currentTime < $p->arrivalTime) $currentTime = $p->arrivalTime;
            $p->waitingTime = $currentTime - $p->arrivalTime;
            $currentTime += $p->burstTime;
            $p->completionTime = $currentTime;
        }
        return $processes;
    }

    public static function printResults(array $results): void {
        $totalWait = 0; $totalTurn = 0;
        foreach ($results as $p) {
            $turnaround = $p->completionTime - $p->arrivalTime;
            echo "  {$p->name}(pid={$p->pid}): wait={$p->waitingTime} turnaround=$turnaround complete={$p->completionTime}\n";
            $totalWait += $p->waitingTime;
            $totalTurn += $turnaround;
        }
        $n = count($results);
        echo "  Avg wait: " . number_format($totalWait / $n, 2) . "\n";
        echo "  Avg turnaround: " . number_format($totalTurn / $n, 2) . "\n";
    }
}

class BankersAlgorithm {
    private array $available;
    private array $processes;

    public function __construct(array $available, array $processes) {
        $this->available = $available;
        $this->processes = $processes;
    }

    public function isSafe(): array {
        $work = $this->available;
        $finish = array_fill(0, count($this->processes), false);
        $safeSeq = [];

        $count = 0;
        while ($count < count($this->processes)) {
            $found = false;
            foreach ($this->processes as $i => $p) {
                if ($finish[$i]) continue;
                $need = $p->remainingNeed();
                $canAllocate = true;
                foreach ($need as $r => $n) {
                    if ($n > ($work[$r] ?? 0)) { $canAllocate = false; break; }
                }
                if ($canAllocate) {
                    foreach ($p->allocated as $r => $amt) $work[$r] = ($work[$r] ?? 0) + $amt;
                    $safeSeq[] = $p->pid;
                    $finish[$i] = true;
                    $count++;
                    $found = true;
                }
            }
            if (!$found) return [];
        }
        return $safeSeq;
    }

    public function requestResources(int $pid, array $request): array {
        $p = null;
        foreach ($this->processes as $proc) { if ($proc->pid === $pid) { $p = $proc; break; } }
        if ($p === null) return ['granted' => false, 'reason' => 'invalid pid'];
        $need = $p->remainingNeed();
        foreach ($request as $r => $amt) {
            if ($amt > ($need[$r] ?? 0)) return ['granted' => false, 'reason' => 'exceeds need'];
            if ($amt > ($this->available[$r] ?? 0)) return ['granted' => false, 'reason' => 'exceeds available'];
        }
        // 试探分配
        foreach ($request as $r => $amt) {
            $this->available[$r] -= $amt;
            $p->allocated[$r] = ($p->allocated[$r] ?? 0) + $amt;
        }
        $safeSeq = $this->isSafe();
        if (!empty($safeSeq)) return ['granted' => true, 'safe_seq' => $safeSeq];
        // 回滚
        foreach ($request as $r => $amt) {
            $this->available[$r] += $amt;
            $p->allocated[$r] -= $amt;
        }
        return ['granted' => false, 'reason' => 'unsafe state'];
    }
}

// 测试
echo "--- CPU Scheduling ---\n";
$procs = [
    new Process(1, 'P1', 6, 0, 2),
    new Process(2, 'P2', 8, 1, 1),
    new Process(3, 'P3', 7, 2, 3),
    new Process(4, 'P4', 3, 3, 1),
];

echo "\nFCFS:\n"; OSScheduler::printResults(OSScheduler::fcfs(array_map(fn($p) => clone $p, $procs)));
echo "\nSJF:\n"; OSScheduler::printResults(OSScheduler::sjf(array_map(fn($p) => clone $p, $procs)));
echo "\nRound Robin (q=2):\n"; OSScheduler::printResults(OSScheduler::roundRobin(array_map(fn($p) => clone $p, $procs), 2));
echo "\nPriority:\n"; OSScheduler::printResults(OSScheduler::priority(array_map(fn($p) => clone $p, $procs)));

echo "\n--- Banker's Algorithm ---\n";
$bankerProcs = [
    new Process(0, 'P0', 0, 0, 0, ['A' => 3, 'B' => 2, 'C' => 2], ['A' => 0, 'B' => 1, 'C' => 0]),
    new Process(1, 'P1', 0, 0, 0, ['A' => 6, 'B' => 1, 'C' => 3], ['A' => 2, 'B' => 1, 'C' => 1]),
    new Process(2, 'P2', 0, 0, 0, ['A' => 3, 'B' => 1, 'C' => 4], ['A' => 2, 'B' => 1, 'C' => 1]),
    new Process(3, 'P3', 0, 0, 0, ['A' => 4, 'B' => 2, 'C' => 2], ['A' => 0, 'B' => 0, 'C' => 2]),
];
$available = ['A' => 3, 'B' => 3, 'C' => 2]; // 10 - (0+2+2+0)=6? 简化

$banker = new BankersAlgorithm($available, array_map(fn($p) => clone $p, $bankerProcs));
$safeSeq = $banker->isSafe();
echo "Safe sequence: " . (empty($safeSeq) ? "NONE (unsafe)" : implode(' → ', $safeSeq)) . "\n";

echo "\nRequest P1 wants [1,0,2]:\n";
$result = $banker->requestResources(1, ['A' => 1, 'B' => 0, 'C' => 2]);
echo "Result: " . json_encode($result) . "\n";

echo "\nRequest P0 wants [0,2,0]:\n";
$result2 = $banker->requestResources(0, ['A' => 0, 'B' => 2, 'C' => 0]);
echo "Result: " . json_encode($result2) . "\n";

echo "=== f091 Done ===\n";
