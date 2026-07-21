<?php
// 极度混搭: 调度器 + 任务优先级 + 依赖图 + 拓扑排序 + 并行模拟
echo "=== f079: Scheduler + Priority + Dependencies + TopoSort ===\n";

class Task {
    public string $status = 'pending';
    public array $dependencies = [];
    public array $dependents = [];
    public int $actualStart = -1;
    public int $actualEnd = -1;

    public function __construct(
        public string $id,
        public string $name,
        public int $priority = 0,
        public int $duration = 1,
    ) {}

    public function addDependency(string $taskId): void {
        $this->dependencies[] = $taskId;
    }

    public function isReady(): bool {
        return $this->status === 'pending' && empty($this->dependencies);
    }
}

class TaskScheduler {
    private array $tasks = [];
    private array $executionOrder = [];
    private int $currentTime = 0;

    public function addTask(Task $task): void {
        $this->tasks[$task->id] = $task;
    }

    public function addDependency(string $taskId, string $dependsOn): void {
        $this->tasks[$taskId]->addDependency($dependsOn);
        $this->tasks[$dependsOn]->dependents[] = $taskId;
    }

    public function topologicalSort(): array {
        $inDegree = [];
        foreach ($this->tasks as $id => $task) {
            $inDegree[$id] = count($task->dependencies);
        }
        $queue = [];
        foreach ($inDegree as $id => $deg) {
            if ($deg === 0) $queue[] = $id;
        }
        $sorted = [];
        while (!empty($queue)) {
            usort($queue, fn($a, $b) => $this->tasks[$b]->priority <=> $this->tasks[$a]->priority);
            $id = array_shift($queue);
            $sorted[] = $id;
            foreach ($this->tasks[$id]->dependents as $dep) {
                $inDegree[$dep]--;
                if ($inDegree[$dep] === 0) $queue[] = $dep;
            }
        }
        if (count($sorted) !== count($this->tasks)) {
            throw new RuntimeException("Cycle detected in task dependencies");
        }
        return $sorted;
    }

    public function schedule(int $workers = 1): array {
        $sorted = $this->topologicalSort();
        $this->executionOrder = [];
        $this->currentTime = 0;
        $inDegree = [];
        foreach ($this->tasks as $id => $task) {
            $inDegree[$id] = count($task->dependencies);
        }
        $available = [];
        $running = [];
        $completed = [];

        foreach ($sorted as $id) {
            if ($inDegree[$id] === 0) $available[] = $id;
        }

        while (!empty($available) || !empty($running)) {
            // 按优先级排序可用任务
            usort($available, fn($a, $b) => $this->tasks[$b]->priority <=> $this->tasks[$a]->priority);
            // 分配给workers
            while (!empty($available) && count($running) < $workers) {
                $id = array_shift($available);
                $task = $this->tasks[$id];
                $task->status = 'running';
                $task->actualStart = $this->currentTime;
                $running[] = $id;
                $this->executionOrder[] = ['time' => $this->currentTime, 'task' => $id, 'action' => 'start'];
            }
            // 完成最早结束的
            if (!empty($running)) {
                usort($running, fn($a, $b) => $this->tasks[$a]->actualEnd <=> $this->tasks[$b]->actualEnd);
                $id = $running[0];
                $task = $this->tasks[$id];
                $this->currentTime = $task->actualStart + $task->duration;
                $task->actualEnd = $this->currentTime;
                $task->status = 'completed';
                $this->executionOrder[] = ['time' => $this->currentTime, 'task' => $id, 'action' => 'complete'];
                $running = array_slice($running, 1);
                $completed[] = $id;
                // 解锁依赖
                foreach ($task->dependents as $dep) {
                    $inDegree[$dep]--;
                    if ($inDegree[$dep] === 0) $available[] = $dep;
                }
            }
        }
        return [
            'order' => array_map(fn($t) => $t['task'], array_filter($this->executionOrder, fn($e) => $e['action'] === 'complete')),
            'total_time' => $this->currentTime,
            'execution' => $this->executionOrder,
        ];
    }

    public function getTasks(): array { return $this->tasks; }
}

// 测试
echo "--- Build Pipeline ---\n";
$scheduler = new TaskScheduler();
$scheduler->addTask(new Task('fetch', 'Fetch Dependencies', 10, 2));
$scheduler->addTask(new Task('lint', 'Lint Code', 5, 1));
$scheduler->addTask(new Task('compile', 'Compile', 8, 3));
$scheduler->addTask(new Task('test', 'Run Tests', 7, 4));
$scheduler->addTask(new Task('pack', 'Package', 3, 2));
$scheduler->addTask(new Task('deploy', 'Deploy', 1, 1));

$scheduler->addDependency('lint', 'fetch');
$scheduler->addDependency('compile', 'fetch');
$scheduler->addDependency('test', 'compile');
$scheduler->addDependency('pack', 'test');
$scheduler->addDependency('pack', 'lint');
$scheduler->addDependency('deploy', 'pack');

echo "Topological order: " . implode(' → ', $scheduler->topologicalSort()) . "\n";

echo "\n--- Single Worker ---\n";
$result = $scheduler->schedule(1);
echo "Total time: {$result['total_time']}\n";
echo "Execution order: " . implode(' → ', $result['order']) . "\n";
foreach ($result['execution'] as $e) {
    $task = $scheduler->getTasks()[$e['task']];
    echo "  t={$e['time']} {$e['action']} {$task->name}\n";
}

echo "\n--- 2 Workers (Parallel) ---\n";
$scheduler2 = new TaskScheduler();
$scheduler2->addTask(new Task('fetch', 'Fetch', 10, 2));
$scheduler2->addTask(new Task('lint', 'Lint', 5, 1));
$scheduler2->addTask(new Task('compile', 'Compile', 8, 3));
$scheduler2->addTask(new Task('test', 'Test', 7, 4));
$scheduler2->addTask(new Task('pack', 'Package', 3, 2));
$scheduler2->addTask(new Task('deploy', 'Deploy', 1, 1));
$scheduler2->addDependency('lint', 'fetch');
$scheduler2->addDependency('compile', 'fetch');
$scheduler2->addDependency('test', 'compile');
$scheduler2->addDependency('pack', 'test');
$scheduler2->addDependency('pack', 'lint');
$scheduler2->addDependency('deploy', 'pack');

$result2 = $scheduler2->schedule(2);
echo "Total time: {$result2['total_time']} (vs {$result['total_time']} with 1 worker)\n";
foreach ($result2['execution'] as $e) {
    $task = $scheduler2->getTasks()[$e['task']];
    echo "  t={$e['time']} {$e['action']} {$task->name}\n";
}

echo "\n--- Cycle Detection ---\n";
$scheduler3 = new TaskScheduler();
$scheduler3->addTask(new Task('a', 'A'));
$scheduler3->addTask(new Task('b', 'B'));
$scheduler3->addTask(new Task('c', 'C'));
$scheduler3->addDependency('b', 'a');
$scheduler3->addDependency('c', 'b');
$scheduler3->addDependency('a', 'c'); // 循环!
try {
    $scheduler3->topologicalSort();
    echo "ERROR: should have detected cycle\n";
} catch (RuntimeException $e) {
    echo "Caught: " . $e->getMessage() . "\n";
}

echo "=== f079 Done ===\n";
