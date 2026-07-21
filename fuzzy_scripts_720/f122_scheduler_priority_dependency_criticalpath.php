<?php
// 极度混搭: 调度器 + 优先级队列 + 依赖图 + 拓扑排序 + 关键路径
echo "=== f122: Scheduler + PriorityQueue + Dependency + CriticalPath ===\n";

class Task {
    public string $status = 'pending';
    public int $actualStart = -1;
    public int $actualEnd = -1;
    public array $dependents = [];

    public function __construct(public string $id, public string $name, public int $priority = 0, public int $duration = 1, public array $dependencies = []) {}
}

class TaskScheduler {
    private array $tasks = [];
    private array $graph = [];

    public function addTask(Task $task): self {
        $this->tasks[$task->id] = $task;
        $this->graph[$task->id] = $task->dependencies;
        return $this;
    }

    public function topologicalSort(): array {
        $inDegree = [];
        foreach ($this->tasks as $id => $task) $inDegree[$id] = 0;
        foreach ($this->graph as $id => $deps) {
            foreach ($deps as $dep) {
                if (isset($this->tasks[$dep])) {
                    $this->tasks[$dep]->dependents[] = $id;
                    $inDegree[$id]++;
                }
            }
        }
        $queue = [];
        foreach ($inDegree as $id => $degree) {
            if ($degree === 0) $queue[] = $id;
        }
        usort($queue, fn($a, $b) => $this->tasks[$b]->priority <=> $this->tasks[$a]->priority);

        $result = [];
        while (!empty($queue)) {
            $current = array_shift($queue);
            $result[] = $current;
            $this->tasks[$current]->status = 'scheduled';
            $next = [];
            foreach ($this->tasks[$current]->dependents as $dep) {
                $inDegree[$dep]--;
                if ($inDegree[$dep] === 0) $next[] = $dep;
            }
            usort($next, fn($a, $b) => $this->tasks[$b]->priority <=> $this->tasks[$a]->priority);
            $queue = array_merge($next, $queue);
            usort($queue, fn($a, $b) => $this->tasks[$b]->priority <=> $this->tasks[$a]->priority);
        }
        return $result;
    }

    public function criticalPath(): array {
        $sorted = $this->topologicalSort();
        $earliestStart = [];
        $earliestFinish = [];
        foreach ($sorted as $id) {
            $task = $this->tasks[$id];
            $es = 0;
            foreach ($task->dependencies as $dep) {
                if (isset($earliestFinish[$dep])) $es = max($es, $earliestFinish[$dep]);
            }
            $earliestStart[$id] = $es;
            $earliestFinish[$id] = $es + $task->duration;
        }
        $totalDuration = max($earliestFinish);
        $latestFinish = [];
        $latestStart = [];
        foreach (array_reverse($sorted) as $id) {
            $task = $this->tasks[$id];
            $lf = $totalDuration;
            foreach ($task->dependents as $dep) {
                if (isset($latestStart[$dep])) $lf = min($lf, $latestStart[$dep]);
            }
            $latestFinish[$id] = $lf;
            $latestStart[$id] = $lf - $task->duration;
        }
        $criticalPath = [];
        foreach ($sorted as $id) {
            $slack = $latestStart[$id] - $earliestStart[$id];
            $isCritical = $slack === 0;
            $criticalPath[] = [
                'task' => $id,
                'name' => $this->tasks[$id]->name,
                'duration' => $this->tasks[$id]->duration,
                'es' => $earliestStart[$id],
                'ef' => $earliestFinish[$id],
                'ls' => $latestStart[$id],
                'lf' => $latestFinish[$id],
                'slack' => $slack,
                'critical' => $isCritical,
            ];
        }
        return ['path' => $criticalPath, 'total_duration' => $totalDuration];
    }

    public function simulate(int $workers = 2): array {
        $order = $this->topologicalSort();
        $completed = [];
        $workerSchedule = [];
        for ($i = 0; $i < $workers; $i++) $workerSchedule[] = ['task' => null, 'endTime' => 0];
        $timeline = [];
        $time = 0;

        while (count($completed) < count($this->tasks)) {
            // 完成已到时间的任务
            for ($w = 0; $w < $workers; $w++) {
                if ($workerSchedule[$w]['task'] !== null && $workerSchedule[$w]['endTime'] <= $time) {
                    $completed[$workerSchedule[$w]['task']] = $time;
                    $this->tasks[$workerSchedule[$w]['task']]->status = 'completed';
                    $this->tasks[$workerSchedule[$w]['task']]->actualEnd = $time;
                    $workerSchedule[$w] = ['task' => null, 'endTime' => 0];
                }
            }
            // 分配新任务
            for ($w = 0; $w < $workers; $w++) {
                if ($workerSchedule[$w]['task'] !== null) continue;
                foreach ($order as $taskId) {
                    $task = $this->tasks[$taskId];
                    if ($task->status !== 'pending') continue;
                    $canStart = true;
                    foreach ($task->dependencies as $dep) {
                        if (!isset($completed[$dep])) { $canStart = false; break; }
                    }
                    if ($canStart) {
                        $task->status = 'running';
                        $task->actualStart = $time;
                        $workerSchedule[$w] = ['task' => $taskId, 'endTime' => $time + $task->duration];
                        $timeline[] = ['time' => $time, 'worker' => $w, 'action' => 'start', 'task' => $taskId];
                        break;
                    }
                }
            }
            // 推进时间
            $nextTime = PHP_INT_MAX;
            for ($w = 0; $w < $workers; $w++) {
                if ($workerSchedule[$w]['task'] !== null && $workerSchedule[$w]['endTime'] < $nextTime) {
                    $nextTime = $workerSchedule[$w]['endTime'];
                }
            }
            if ($nextTime === PHP_INT_MAX) break;
            $time = $nextTime;
        }
        return ['timeline' => $timeline, 'totalTime' => $time, 'completed' => count($completed)};
    }

    public function detectCycle(): ?array {
        $WHITE = 0; $GRAY = 1; $BLACK = 2;
        $color = array_fill_keys(array_keys($this->tasks), $WHITE);
        $path = [];
        foreach ($this->tasks as $id => $_) {
            if ($color[$id] === $WHITE) {
                $cycle = $this->dfsCycle($id, $color, $path);
                if ($cycle !== null) return $cycle;
            }
        }
        return null;
    }

    private function dfsCycle(string $node, array &$color, array &$path): ?array {
        $color[$node] = $GRAY;
        $path[] = $node;
        foreach ($this->tasks[$node]->dependents as $neighbor) {
            if ($color[$neighbor] === $GRAY) {
                $cycleStart = array_search($neighbor, $path);
                return array_slice($path, $cycleStart);
            }
            if ($color[$neighbor] === $WHITE) {
                $cycle = $this->dfsCycle($neighbor, $color, $path);
                if ($cycle !== null) return $cycle;
            }
        }
        $color[$node] = $BLACK;
        array_pop($path);
        return null;
    }
}

// 测试
echo "--- Task Scheduler with Dependencies ---\n";
$scheduler = new TaskScheduler();
$scheduler->addTask(new Task('A', 'Design', 5, 3, []));
$scheduler->addTask(new Task('B', 'Backend API', 4, 5, ['A']));
$scheduler->addTask(new Task('C', 'Frontend', 3, 4, ['A']));
$scheduler->addTask(new Task('D', 'Database', 4, 3, ['A']));
$scheduler->addTask(new Task('E', 'Integration', 2, 4, ['B', 'C', 'D']));
$scheduler->addTask(new Task('F', 'Testing', 3, 5, ['E']));
$scheduler->addTask(new Task('G', 'Deploy', 1, 2, ['F']));
$scheduler->addTask(new Task('H', 'Docs', 0, 3, ['A']));

echo "\n--- Topological Sort (priority) ---\n";
$order = $scheduler->topologicalSort();
echo "Order: " . implode(' → ', $order) . "\n";

echo "\n--- Critical Path ---\n";
$cp = $scheduler->criticalPath();
echo "Total duration: {$cp['total_duration']} units\n";
echo str_pad('Task', 6) . str_pad('Name', 15) . str_pad('Dur', 5) . str_pad('ES', 5) . str_pad('EF', 5) . str_pad('LS', 5) . str_pad('LF', 5) . str_pad('Slack', 6) . "Critical\n";
foreach ($cp['path'] as $p) {
    echo str_pad($p['task'], 6) . str_pad($p['name'], 15) . str_pad($p['duration'], 5) . str_pad($p['es'], 5) . str_pad($p['ef'], 5) . str_pad($p['ls'], 5) . str_pad($p['lf'], 5) . str_pad($p['slack'], 6) . ($p['critical'] ? '★' : '') . "\n";
}
$criticalTasks = array_filter($cp['path'], fn($p) => $p['critical']);
echo "Critical path: " . implode(' → ', array_map(fn($p) => $p['task'], $criticalTasks)) . "\n";

echo "\n--- Simulate (2 workers) ---\n";
$sim2 = $scheduler->simulate(2);
echo "2 workers: total time = {$sim2['totalTime']}, completed = {$sim2['completed']}\n";
echo "Timeline:\n";
foreach ($sim2['timeline'] as $t) echo "  t={$t['time']} worker={$t['worker']} {$t['action']} task={$t['task']}\n";

echo "\n--- Simulate (3 workers) ---\n";
$scheduler2 = new TaskScheduler();
$scheduler2->addTask(new Task('A', 'Design', 5, 3, []));
$scheduler2->addTask(new Task('B', 'Backend API', 4, 5, ['A']));
$scheduler2->addTask(new Task('C', 'Frontend', 3, 4, ['A']));
$scheduler2->addTask(new Task('D', 'Database', 4, 3, ['A']));
$scheduler2->addTask(new Task('E', 'Integration', 2, 4, ['B', 'C', 'D']));
$scheduler2->addTask(new Task('F', 'Testing', 3, 5, ['E']));
$scheduler2->addTask(new Task('G', 'Deploy', 1, 2, ['F']));
$scheduler2->addTask(new Task('H', 'Docs', 0, 3, ['A']));
$sim3 = $scheduler2->simulate(3);
echo "3 workers: total time = {$sim3['totalTime']}, completed = {$sim3['completed']}\n";

echo "\n--- Simulate (4 workers) ---\n";
$scheduler3 = new TaskScheduler();
$scheduler3->addTask(new Task('A', 'Design', 5, 3, []));
$scheduler3->addTask(new Task('B', 'Backend API', 4, 5, ['A']));
$scheduler3->addTask(new Task('C', 'Frontend', 3, 4, ['A']));
$scheduler3->addTask(new Task('D', 'Database', 4, 3, ['A']));
$scheduler3->addTask(new Task('E', 'Integration', 2, 4, ['B', 'C', 'D']));
$scheduler3->addTask(new Task('F', 'Testing', 3, 5, ['E']));
$scheduler3->addTask(new Task('G', 'Deploy', 1, 2, ['F']));
$scheduler3->addTask(new Task('H', 'Docs', 0, 3, ['A']));
$sim4 = $scheduler3->simulate(4);
echo "4 workers: total time = {$sim4['totalTime']}\n";

echo "\n--- Cycle Detection ---\n";
$cyclic = new TaskScheduler();
$cyclic->addTask(new Task('X', 'X', 1, 1, ['Z']));
$cyclic->addTask(new Task('Y', 'Y', 1, 1, ['X']));
$cyclic->addTask(new Task('Z', 'Z', 1, 1, ['Y']));
$cycle = $cyclic->detectCycle();
echo "Cycle detected: " . ($cycle ? implode(' → ', $cycle) : 'none') . "\n";

$noCycle = new TaskScheduler();
$noCycle->addTask(new Task('P', 'P', 1, 1, []));
$noCycle->addTask(new Task('Q', 'Q', 1, 1, ['P']));
echo "No-cycle check: " . ($noCycle->detectCycle() ? 'has cycle' : 'no cycle') . "\n";

echo "=== f122 Done ===\n";
