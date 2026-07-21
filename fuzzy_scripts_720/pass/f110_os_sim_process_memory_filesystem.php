<?php
// 极度混搭: 操作系统模拟 + 进程调度 + 内存分配 + 文件系统
echo "=== f110: OS Sim + Process + Memory + FileSystem ===\n";

class Process {
    public string $state = 'ready'; // ready, running, waiting, terminated
    public int $pc = 0;
    public array $registers = [];
    public int $startTime = 0;
    public int $cpuTime = 0;
    public int $waitingTime = 0;
    public array $openFiles = [];

    public function __construct(public int $pid, public string $name, public int $priority = 0, public int $burstTime = 10) {}
}

class CPUScheduler {
    private array $processes = [];
    private array $readyQueue = [];
    private ?Process $current = null;
    private int $time = 0;
    private array $gantt = [];

    public function addProcess(Process $p): void { $this->processes[$p->pid] = $p; $this->readyQueue[] = $p; }

    public function runFCFS(): array {
        $this->time = 0; $this->gantt = [];
        $queue = $this->readyQueue;
        foreach ($queue as $p) {
            $p->state = 'running';
            $this->gantt[] = ['pid' => $p->pid, 'start' => $this->time, 'end' => $this->time + $p->burstTime];
            $this->time += $p->burstTime;
            $p->cpuTime = $p->burstTime;
            $p->state = 'terminated';
        }
        return $this->gantt;
    }

    public function runRoundRobin(int $quantum = 2): array {
        $this->time = 0; $this->gantt = [];
        $remaining = [];
        foreach ($this->readyQueue as $p) $remaining[$p->pid] = $p->burstTime;
        $queue = $this->readyQueue;
        while (!empty($queue)) {
            $p = array_shift($queue);
            $exec = min($quantum, $remaining[$p->pid]);
            $this->gantt[] = ['pid' => $p->pid, 'start' => $this->time, 'end' => $this->time + $exec];
            $this->time += $exec;
            $remaining[$p->pid] -= $exec;
            $p->cpuTime += $exec;
            if ($remaining[$p->pid] > 0) $queue[] = $p;
            else $p->state = 'terminated';
        }
        return $this->gantt;
    }

    public function runPriority(): array {
        $this->time = 0; $this->gantt = [];
        $queue = $this->readyQueue;
        usort($queue, fn($a, $b) => $a->priority <=> $b->priority);
        foreach ($queue as $p) {
            $p->state = 'running';
            $this->gantt[] = ['pid' => $p->pid, 'start' => $this->time, 'end' => $this->time + $p->burstTime];
            $this->time += $p->burstTime;
            $p->cpuTime = $p->burstTime;
            $p->state = 'terminated';
        }
        return $this->gantt;
    }

    public function runSJF(): array {
        $this->time = 0; $this->gantt = [];
        $queue = $this->readyQueue;
        usort($queue, fn($a, $b) => $a->burstTime <=> $b->burstTime);
        foreach ($queue as $p) {
            $p->state = 'running';
            $this->gantt[] = ['pid' => $p->pid, 'start' => $this->time, 'end' => $this->time + $p->burstTime];
            $this->time += $p->burstTime;
            $p->cpuTime = $p->burstTime;
            $p->state = 'terminated';
        }
        return $this->gantt;
    }

    public function getAvgWaitTime(array $gantt, array $processes): float {
        $completion = [];
        foreach ($gantt as $item) $completion[$item['pid']] = $item['end'];
        $totalWait = 0; $count = 0;
        foreach ($processes as $p) {
            if (isset($completion[$p->pid])) {
                $wait = $completion[$p->pid] - $p->burstTime;
                $totalWait += $wait;
                $count++;
            }
        }
        return $count > 0 ? $totalWait / $count : 0;
    }
}

class MemoryManager {
    private array $blocks = [];
    private array $allocated = [];
    private int $totalSize;

    public function __construct(int $size = 1024) {
        $this->totalSize = $size;
        $this->blocks = [['start' => 0, 'size' => $size, 'free' => true]];
    }

    public function allocate(int $size, string $strategy = 'first'): ?int {
        $idx = match($strategy) {
            'first' => $this->findFirstFit($size),
            'best' => $this->findBestFit($size),
            'worst' => $this->findWorstFit($size),
            default => $this->findFirstFit($size),
        };
        if ($idx === null) return null;
        $block = $this->blocks[$idx];
        $addr = $block['start'];
        if ($block['size'] > $size) {
            $this->blocks[$idx] = ['start' => $addr + $size, 'size' => $block['size'] - $size, 'free' => true];
        } else {
            $this->blocks[$idx]['free'] = false;
        }
        $this->allocated[$addr] = $size;
        return $addr;
    }

    public function deallocate(int $addr): bool {
        if (!isset($this->allocated[$addr])) return false;
        $size = $this->allocated[$addr];
        unset($this->allocated[$addr]);
        $this->blocks[] = ['start' => $addr, 'size' => $size, 'free' => true];
        $this->mergeBlocks();
        return true;
    }

    private function findFirstFit(int $size): ?int {
        foreach ($this->blocks as $i => $block) {
            if ($block['free'] && $block['size'] >= $size) return $i;
        }
        return null;
    }

    private function findBestFit(int $size): ?int {
        $best = null; $bestSize = PHP_INT_MAX;
        foreach ($this->blocks as $i => $block) {
            if ($block['free'] && $block['size'] >= $size && $block['size'] < $bestSize) {
                $best = $i; $bestSize = $block['size'];
            }
        }
        return $best;
    }

    private function findWorstFit(int $size): ?int {
        $worst = null; $worstSize = 0;
        foreach ($this->blocks as $i => $block) {
            if ($block['free'] && $block['size'] >= $size && $block['size'] > $worstSize) {
                $worst = $i; $worstSize = $block['size'];
            }
        }
        return $worst;
    }

    private function mergeBlocks(): void {
        usort($this->blocks, fn($a, $b) => $a['start'] <=> $b['start']);
        $merged = [];
        foreach ($this->blocks as $block) {
            if (!empty($merged) && $merged[count($merged) - 1]['free'] && $block['free'] &&
                $merged[count($merged) - 1]['start'] + $merged[count($merged) - 1]['size'] === $block['start']) {
                $merged[count($merged) - 1]['size'] += $block['size'];
            } else {
                $merged[] = $block;
            }
        }
        $this->blocks = $merged;
    }

    public function getStats(): array {
        $free = 0; $used = 0;
        foreach ($this->blocks as $b) { if ($b['free']) $free += $b['size']; else $used += $b['size']; }
        $used += array_sum($this->allocated);
        return ['total' => $this->totalSize, 'free' => $free, 'used' => $used, 'fragments' => count(array_filter($this->blocks, fn($b) => $b['free']))];
    }
}

class VirtualFS {
    private array $root = [];

    public function mkdir(string $path): bool {
        $parts = $this->splitPath($path);
        $current = &$this->root;
        foreach ($parts as $part) {
            if (!isset($current[$part])) $current[$part] = ['type' => 'dir', 'children' => []];
            if ($current[$part]['type'] !== 'dir') return false;
            $current = &$current[$part]['children'];
        }
        return true;
    }

    public function writeFile(string $path, string $content): bool {
        $parts = $this->splitPath($path);
        $filename = array_pop($parts);
        $current = &$this->root;
        foreach ($parts as $part) {
            if (!isset($current[$part])) return false;
            if ($current[$part]['type'] !== 'dir') return false;
            $current = &$current[$part]['children'];
        }
        $current[$filename] = ['type' => 'file', 'content' => $content, 'size' => strlen($content)];
        return true;
    }

    public function readFile(string $path): ?string {
        $parts = $this->splitPath($path);
        $filename = array_pop($parts);
        $current = &$this->root;
        foreach ($parts as $part) {
            if (!isset($current[$part])) return null;
            $current = &$current[$part]['children'];
        }
        return $current[$filename]['content'] ?? null;
    }

    public function listDir(string $path = '/'): array {
        if ($path === '/') return array_keys($this->root);
        $parts = $this->splitPath($path);
        $current = &$this->root;
        foreach ($parts as $part) {
            if (!isset($current[$part])) return [];
            $current = &$current[$part]['children'];
        }
        return array_keys($current);
    }

    public function delete(string $path): bool {
        $parts = $this->splitPath($path);
        $name = array_pop($parts);
        $current = &$this->root;
        foreach ($parts as $part) {
            if (!isset($current[$part])) return false;
            $current = &$current[$part]['children'];
        }
        if (!isset($current[$name])) return false;
        unset($current[$name]);
        return true;
    }

    private function splitPath(string $path): array {
        return array_values(array_filter(explode('/', $path)));
    }
}

// 测试
echo "--- CPU Scheduling ---\n";
$scheduler = new CPUScheduler();
$scheduler->addProcess(new Process(1, 'P1', 3, 5));
$scheduler->addProcess(new Process(2, 'P2', 1, 3));
$scheduler->addProcess(new Process(3, 'P3', 2, 8));
$scheduler->addProcess(new Process(4, 'P4', 4, 6));

$processes = [
    new Process(1, 'P1', 3, 5),
    new Process(2, 'P2', 1, 3),
    new Process(3, 'P3', 2, 8),
    new Process(4, 'P4', 4, 6),
];

echo "FCFS:\n";
$gantt = $scheduler->runFCFS();
foreach ($gantt as $g) echo "  P{$g['pid']}: [{$g['start']}, {$g['end']}]\n";

echo "\nRound Robin (q=2):\n";
$scheduler2 = new CPUScheduler();
foreach ($processes as $p) $scheduler2->addProcess($p);
$gantt = $scheduler2->runRoundRobin(2);
foreach ($gantt as $g) echo "  P{$g['pid']}: [{$g['start']}, {$g['end']}]\n";

echo "\nPriority:\n";
$scheduler3 = new CPUScheduler();
foreach ($processes as $p) $scheduler3->addProcess($p);
$gantt = $scheduler3->runPriority();
foreach ($gantt as $g) echo "  P{$g['pid']}: [{$g['start']}, {$g['end']}]\n";

echo "\nSJF:\n";
$scheduler4 = new CPUScheduler();
foreach ($processes as $p) $scheduler4->addProcess($p);
$gantt = $scheduler4->runSJF();
foreach ($gantt as $g) echo "  P{$g['pid']}: [{$g['start']}, {$g['end']}]\n";

echo "\n--- Memory Management ---\n";
$mem = new MemoryManager(1024);
$addr1 = $mem->allocate(128, 'first');
$addr2 = $mem->allocate(256, 'first');
$addr3 = $mem->allocate(64, 'first');
echo "Allocated: addr1=$addr1 (128B), addr2=$addr2 (256B), addr3=$addr3 (64B)\n";
echo "Stats: " . json_encode($mem->getStats()) . "\n";

$mem->deallocate($addr2);
echo "After dealloc addr2: " . json_encode($mem->getStats()) . "\n";

$addr4 = $mem->allocate(128, 'best');
echo "Best fit alloc 128B at: $addr4\n";
echo "Stats: " . json_encode($mem->getStats()) . "\n";

$addr5 = $mem->allocate(200, 'worst');
echo "Worst fit alloc 200B at: $addr5\n";
echo "Stats: " . json_encode($mem->getStats()) . "\n";

echo "\n--- File System ---\n";
$fs = new VirtualFS();
$fs->mkdir('/home');
$fs->mkdir('/home/user');
$fs->mkdir('/etc');
$fs->mkdir('/var/log');
$fs->writeFile('/home/user/readme.txt', 'Hello World');
$fs->writeFile('/etc/config.ini', 'key=value');
$fs->writeFile('/var/log/app.log', 'Application started');

echo "Root: " . implode(', ', $fs->listDir('/')) . "\n";
echo "home: " . implode(', ', $fs->listDir('/home')) . "\n";
echo "home/user: " . implode(', ', $fs->listDir('/home/user')) . "\n";
echo "Readme: " . $fs->readFile('/home/user/readme.txt') . "\n";
echo "Config: " . $fs->readFile('/etc/config.ini') . "\n";

$fs->delete('/home/user/readme.txt');
echo "After delete readme, home/user: " . implode(', ', $fs->listDir('/home/user')) . "\n";

echo "=== f110 Done ===\n";
