<?php
// 工作流引擎：任务编排/条件分支/并行执行
echo "=== Workflow Engine ===\n\n";

class WorkflowTask {
    public string $id;
    public string $name;
    public $execute;
    public $condition;
    public array $dependencies = [];
    public string $status = 'pending';
    public mixed $result = null;
    public ?string $error = null;
    public float $duration = 0;

    public function __construct(string $id, string $name, callable $execute, ?callable $condition = null) {
        $this->id = $id;
        $this->name = $name;
        $this->execute = $execute;
        $this->condition = $condition;
    }

    public function dependsOn(string ...$ids): self {
        $this->dependencies = [...$this->dependencies, ...$ids];
        return $this;
    }

    public function canRun(array $completedTasks): bool {
        if ($this->status !== 'pending') return false;
        foreach ($this->dependencies as $dep) {
            if (!isset($completedTasks[$dep]) || $completedTasks[$dep]->status !== 'completed') {
                return false;
            }
        }
        if ($this->condition !== null) {
            return ($this->condition)($completedTasks);
        }
        return true;
    }

    public function run(array $context = []): void {
        $start = microtime(true);
        $this->status = 'running';
        try {
            $this->result = ($this->execute)($context);
            $this->status = 'completed';
        } catch (Throwable $e) {
            $this->error = $e->getMessage();
            $this->status = 'failed';
        }
        $this->duration = (microtime(true) - $start) * 1000;
    }
}

class Workflow {
    public string $name;
    private array $tasks = [];
    private array $results = [];
    private bool $stopOnFailure = false;
    private array $executionOrder = [];

    public function __construct(string $name) { $this->name = $name; }

    public function addTask(WorkflowTask $task): self {
        $this->tasks[$task->id] = $task;
        return $this;
    }

    public function setStopOnFailure(bool $stop): self {
        $this->stopOnFailure = $stop;
        return $this;
    }

    public function execute(): array {
        $completed = [];
        $failed = [];
        $skipped = [];
        $context = [];

        while (true) {
            $ranAny = false;
            foreach ($this->tasks as $task) {
                if ($task->canRun($completed)) {
                    $task->run($context);
                    $this->executionOrder[] = $task->id;

                    if ($task->status === 'completed') {
                        $completed[$task->id] = $task;
                        $context[$task->id] = $task->result;
                        $this->results[$task->id] = $task->result;
                    } else {
                        $failed[$task->id] = $task;
                        if ($this->stopOnFailure) {
                            // Mark remaining as skipped
                            foreach ($this->tasks as $t) {
                                if ($t->status === 'pending') {
                                    $t->status = 'skipped';
                                    $skipped[$t->id] = $t;
                                }
                            }
                            break 2;
                        }
                    }
                    $ranAny = true;
                }
            }

            if (!$ranAny) break;

            // Check if all tasks are done or failed
            $pending = array_filter($this->tasks, fn($t) => $t->status === 'pending');
            if (empty($pending)) break;
        }

        // Mark unrunnable as skipped
        foreach ($this->tasks as $task) {
            if ($task->status === 'pending') {
                $task->status = 'skipped';
                $skipped[$task->id] = $task;
            }
        }

        return [
            'completed' => array_keys($completed),
            'failed' => array_keys($failed),
            'skipped' => array_keys($skipped),
            'executionOrder' => $this->executionOrder,
            'results' => $this->results,
        ];
    }

    public function getTask(string $id): ?WorkflowTask { return $this->tasks[$id] ?? null; }
    public function getTasks(): array { return $this->tasks; }

    public function getSummary(): array {
        $summary = [];
        foreach ($this->tasks as $task) {
            $summary[] = [
                'id' => $task->id,
                'name' => $task->name,
                'status' => $task->status,
                'duration_ms' => round($task->duration, 3),
                'deps' => $task->dependencies,
                'error' => $task->error,
            ];
        }
        return $summary;
    }
}

// === 测试 ===

echo "--- Simple Linear Workflow ---\n";
$wf1 = new Workflow('Data Pipeline');
$wf1->addTask((new WorkflowTask('fetch', 'Fetch Data', fn($ctx) => 'raw_data'))->dependsOn());
$wf1->addTask((new WorkflowTask('parse', 'Parse Data', fn($ctx) => strtoupper($ctx['fetch'])))->dependsOn('fetch'));
$wf1->addTask((new WorkflowTask('validate', 'Validate Data', fn($ctx) => strlen($ctx['parse']) > 0))->dependsOn('parse'));
$wf1->addTask((new WorkflowTask('save', 'Save Results', fn($ctx) => "saved: {$ctx['validate']}"))->dependsOn('validate'));

$result = $wf1->execute();
echo "Execution order: " . implode(' -> ', $result['executionOrder']) . "\n";
echo "Completed: " . implode(', ', $result['completed']) . "\n";
echo "Results: " . json_encode($result['results']) . "\n";

echo "\n--- Conditional Branching ---\n";
$wf2 = new Workflow('Order Processing');
$wf2->addTask(new WorkflowTask('validate', 'Validate Order', fn($ctx) => ['valid' => true, 'total' => 150]));
$wf2->addTask(new WorkflowTask(
    'check_stock', 'Check Stock',
    fn($ctx) => ['in_stock' => true, 'warehouse' => 'WH-A'],
    fn($ctx) => ($ctx['validate']->result ?? [])['valid'] ?? false
));
$wf2->addTask((new WorkflowTask(
    'charge_card', 'Charge Credit Card',
    fn($ctx) => ['charged' => true, 'amount' => ($ctx['validate']->result ?? [])['total'] ?? 0]
))->dependsOn('validate'));
$wf2->addTask((new WorkflowTask(
    'ship', 'Ship Order',
    fn($ctx) => ['tracking' => 'TRK123', 'warehouse' => ($ctx['check_stock']->result ?? [])['warehouse'] ?? 'unknown']
))->dependsOn('check_stock', 'charge_card'));
$wf2->addTask((new WorkflowTask(
    'notify', 'Send Notification',
    fn($ctx) => ['email_sent' => true, 'to' => 'customer@email.com']
))->dependsOn('ship'));

$result = $wf2->execute();
echo "Execution order: " . implode(' -> ', $result['executionOrder']) . "\n";
foreach ($wf2->getSummary() as $task) {
    echo "  {$task['id']}: {$task['status']} ({$task['duration_ms']}ms)\n";
}

echo "\n--- Failure Handling ---\n";
$wf3 = new Workflow('Error Pipeline');
$wf3->setStopOnFailure(true);
$wf3->addTask(new WorkflowTask('step1', 'Step 1', fn($ctx) => 'ok1'));
$wf3->addTask(new WorkflowTask('step2', 'Step 2', function($ctx) {
    throw new RuntimeException('Step 2 failed intentionally');
}));
$wf3->addTask((new WorkflowTask('step3', 'Step 3', fn($ctx) => 'ok3'))->dependsOn('step2'));
$wf3->addTask((new WorkflowTask('step4', 'Step 4', fn($ctx) => 'ok4'))->dependsOn('step3'));

$result = $wf3->execute();
echo "Completed: " . implode(', ', $result['completed']) . "\n";
echo "Failed: " . implode(', ', $result['failed']) . "\n";
echo "Skipped: " . implode(', ', $result['skipped']) . "\n";

foreach ($wf3->getSummary() as $task) {
    $error = $task['error'] ? " ERROR: {$task['error']}" : '';
    echo "  {$task['id']}: {$task['status']}{$error}\n";
}

echo "\n--- Parallel Execution ---\n";
$wf4 = new Workflow('Parallel Processing');
$wf4->addTask(new WorkflowTask('init', 'Initialize', fn($ctx) => 'initialized'));
// 3 parallel tasks after init
$wf4->addTask((new WorkflowTask('fetch_a', 'Fetch A', fn($ctx) => 'data_a'))->dependsOn('init'));
$wf4->addTask((new WorkflowTask('fetch_b', 'Fetch B', fn($ctx) => 'data_b'))->dependsOn('init'));
$wf4->addTask((new WorkflowTask('fetch_c', 'Fetch C', fn($ctx) => 'data_c'))->dependsOn('init'));
// Merge after all parallel tasks
$wf4->addTask((new WorkflowTask('merge', 'Merge Results', fn($ctx) => [
    'a' => $ctx['fetch_a'], 'b' => $ctx['fetch_b'], 'c' => $ctx['fetch_c']
]))->dependsOn('fetch_a', 'fetch_b', 'fetch_c'));
$wf4->addTask((new WorkflowTask('finalize', 'Finalize', fn($ctx) => 'done'))->dependsOn('merge'));

$result = $wf4->execute();
echo "Execution order: " . implode(' -> ', $result['executionOrder']) . "\n";
echo "Merge result: " . json_encode($result['results']['merge']) . "\n";

echo "\n--- Complex Workflow Summary ---\n";
foreach ($wf4->getSummary() as $task) {
    echo sprintf("  %-10s %-20s %-10s deps=[%s] %.2fms\n",
        $task['id'], $task['name'], $task['status'],
        implode(',', $task['deps']), $task['duration_ms']);
}
