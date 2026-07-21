<?php
// 极度混搭: 工作流引擎 + BPMN + 网关 + 子流程 + 补偿
echo "=== f147: Workflow Engine + BPMN + Gateway + SubProcess + Compensation ===\n";

class WorkflowTask {
    public string $status = 'pending';
    public ?string $assignee = null;
    public array $outputs = [];
    public float $startTime = 0;
    public float $endTime = 0;

    public function __construct(public string $id, public string $name, public $handler, public string $type = 'service') {}
}

class Gateway {
    public function __construct(public string $id, public string $type, public array $conditions = []) {}
    // type: exclusive, parallel, inclusive
}

class WorkflowDefinition {
    public array $tasks = [];
    public array $gateways = [];
    public array $flows = [];

    public function addTask(WorkflowTask $task): self { $this->tasks[$task->id] = $task; return $this; }
    public function addGateway(Gateway $gw): self { $this->gateways[$gw->id] = $gw; return $this; }
    public function addFlow(string $from, string $to, ?string $condition = null): self { $this->flows[] = ['from' => $from, 'to' => $to, 'condition' => $condition]; return $this; }
}

class WorkflowInstance {
    public string $status = 'running';
    public array $taskResults = [];
    public array $variables = [];
    public array $history = [];
    public array $compensations = [];

    public function __construct(public string $id, public WorkflowDefinition $definition, public array $initialVariables = []) {
        $this->variables = $initialVariables;
    }

    public function execute(): array {
        $this->history[] = "Workflow {$this->id} started";
        $this->runFrom('start');
        $this->history[] = "Workflow {$this->id} {$this->status}";
        return ['status' => $this->status, 'results' => $this->taskResults, 'variables' => $this->variables];
    }

    private function runFrom(string $nodeId): void {
        $visited = [];
        $queue = [$nodeId];
        while (!empty($queue)) {
            $current = array_shift($queue);
            if (isset($visited[$current])) continue;
            $visited[$current] = true;

            if ($current === 'start') {
                $next = $this->getOutgoing($current);
                $queue = array_merge($queue, array_column($next, 'to'));
                continue;
            }
            if ($current === 'end') { $this->status = 'completed'; return; }
            if (isset($this->definition->tasks[$current])) {
                $this->executeTask($this->definition->tasks[$current]);
                $next = $this->getOutgoing($current);
                $queue = array_merge($queue, array_column($next, 'to'));
                continue;
            }
            if (isset($this->definition->gateways[$current])) {
                $next = $this->evaluateGateway($this->definition->gateways[$current]);
                $queue = array_merge($queue, $next);
                continue;
            }
        }
    }

    private function executeTask(WorkflowTask $task): void {
        $task->status = 'running';
        $task->startTime = microtime(true);
        $this->history[] = "Task {$task->name} started";
        try {
            $handler = $task->handler;
            $result = is_callable($handler) ? $handler($this->variables) : null;
            $task->outputs = is_array($result) ? $result : ['result' => $result];
            $task->status = 'completed';
            $this->taskResults[$task->id] = $task->outputs;
            if (is_array($result)) $this->variables = array_merge($this->variables, $result);
        } catch (Exception $e) {
            $task->status = 'failed';
            $this->status = 'failed';
            $this->history[] = "Task {$task->name} failed: {$e->getMessage()}";
            $this->runCompensations();
        }
        $task->endTime = microtime(true);
        $this->history[] = "Task {$task->name} {$task->status}";
    }

    private function evaluateGateway(Gateway $gw): array {
        $outgoing = $this->getOutgoing($gw->id);
        if ($gw->type === 'exclusive') {
            foreach ($outgoing as $flow) {
                if ($flow['condition'] !== null) {
                    $condition = $flow['condition'];
                    if (is_callable($condition) && $condition($this->variables)) return [$flow['to']];
                    if (is_string($condition) && ($this->variables[$condition] ?? false)) return [$flow['to']];
                }
            }
            return !empty($outgoing) ? [$outgoing[0]['to']] : [];
        }
        if ($gw->type === 'parallel') {
            return array_column($outgoing, 'to');
        }
        if ($gw->type === 'inclusive') {
            $results = [];
            foreach ($outgoing as $flow) {
                if ($flow['condition'] !== null) {
                    $condition = $flow['condition'];
                    if (is_callable($condition) && $condition($this->variables)) $results[] = $flow['to'];
                }
            }
            return $results;
        }
        return [];
    }

    private function getOutgoing(string $nodeId): array {
        return array_values(array_filter($this->definition->flows, fn($f) => $f['from'] === $nodeId));
    }

    public function addCompensation(string $taskId, callable $compensation): void { $this->compensations[$taskId] = $compensation; }

    private function runCompensations(): void {
        $this->history[] = "Running compensations...";
        $completedTasks = array_filter($this->definition->tasks, fn($t) => $t->status === 'completed');
        foreach (array_reverse($completedTasks) as $task) {
            if (isset($this->compensations[$task->id])) {
                $comp = $this->compensations[$task->id];
                $comp($this->variables);
                $this->history[] = "Compensation for {$task->name} executed";
            }
        }
    }

    public function getHistory(): array { return $this->history; }
}

class SubProcess {
    public function __construct(public string $id, public WorkflowDefinition $definition) {}

    public function execute(array $variables): array {
        $instance = new WorkflowInstance(uniqid(), $this->definition, $variables);
        return $instance->execute();
    }
}

// 测试
echo "--- Order Processing Workflow ---\n";
$def = new WorkflowDefinition();

$def->addTask(new WorkflowTask('receive_order', 'Receive Order', fn($v) => ['orderId' => $v['orderId'] ?? 1, 'amount' => $v['amount'] ?? 100]));
$def->addTask(new WorkflowTask('validate_order', 'Validate Order', fn($v) => ['valid' => ($v['amount'] ?? 0) > 0]));
$def->addTask(new WorkflowTask('process_payment', 'Process Payment', fn($v) => ['paymentId' => 'PAY-' . ($v['orderId'] ?? 1), 'paid' => true]));
$def->addTask(new WorkflowTask('check_inventory', 'Check Inventory', fn($v) => ['inStock' => true]));
$def->addTask(new WorkflowTask('ship_order', 'Ship Order', fn($v) => ['trackingNumber' => 'TRK-' . uniqid()]));
$def->addTask(new WorkflowTask('send_notification', 'Send Notification', fn($v) => ['notified' => true]));

$def->addGateway(new Gateway('payment_check', 'exclusive'));
$def->addGateway(new Gateway('inventory_check', 'exclusive'));

$def->addFlow('start', 'receive_order');
$def->addFlow('receive_order', 'validate_order');
$def->addFlow('validate_order', 'process_payment');
$def->addFlow('process_payment', 'payment_check');
$def->addFlow('payment_check', 'check_inventory', fn($v) => ($v['paid'] ?? false) === true);
$def->addFlow('payment_check', 'send_notification', fn($v) => ($v['paid'] ?? false) === false);
$def->addFlow('check_inventory', 'inventory_check');
$def->addFlow('inventory_check', 'ship_order', fn($v) => ($v['inStock'] ?? false) === true);
$def->addFlow('inventory_check', 'send_notification', fn($v) => ($v['inStock'] ?? false) === false);
$def->addFlow('ship_order', 'send_notification');
$def->addFlow('send_notification', 'end');

$instance = new WorkflowInstance('order-001', $def, ['orderId' => 42, 'amount' => 199.99]);
$instance->addCompensation('process_payment', function($v) { echo "  [Compensation] Refunding payment for order {$v['orderId']}\n"; });
$instance->addCompensation('ship_order', function($v) { echo "  [Compensation] Cancelling shipment {$v['trackingNumber']}\n"; });

$result = $instance->execute();
echo "Status: {$result['status']}\n";
echo "Variables: " . json_encode($result['variables']) . "\n";

echo "\n--- Workflow History ---\n";
foreach ($instance->getHistory() as $entry) echo "  $entry\n";

echo "\n--- Parallel Gateway Workflow ---\n";
$def2 = new WorkflowDefinition();
$def2->addTask(new WorkflowTask('parallel_a', 'Task A', fn($v) => ['resultA' => 'done']));
$def2->addTask(new WorkflowTask('parallel_b', 'Task B', fn($v) => ['resultB' => 'done']));
$def2->addTask(new WorkflowTask('parallel_c', 'Task C', fn($v) => ['resultC' => 'done']));
$def2->addTask(new WorkflowTask('merge', 'Merge Results', fn($v) => ['merged' => true, 'parts' => [$v['resultA'] ?? null, $v['resultB'] ?? null, $v['resultC'] ?? null]]));

$def2->addGateway(new Gateway('fork', 'parallel'));
$def2->addGateway(new Gateway('join', 'parallel'));

$def2->addFlow('start', 'fork');
$def2->addFlow('fork', 'parallel_a');
$def2->addFlow('fork', 'parallel_b');
$def2->addFlow('fork', 'parallel_c');
$def2->addFlow('parallel_a', 'join');
$def2->addFlow('parallel_b', 'join');
$def2->addFlow('parallel_c', 'join');
$def2->addFlow('join', 'merge');
$def2->addFlow('merge', 'end');

$instance2 = new WorkflowInstance('parallel-001', $def2);
$result2 = $instance2->execute();
echo "Status: {$result2['status']}\n";
echo "Results: " . json_encode($result2['results']) . "\n";

echo "\n--- Compensation Workflow ---\n";
$def3 = new WorkflowDefinition();
$def3->addTask(new WorkflowTask('step1', 'Step 1', fn($v) => ['step1Done' => true]));
$def3->addTask(new WorkflowTask('step2', 'Step 2', fn($v) => ['step2Done' => true]));
$def3->addTask(new WorkflowTask('step3_fail', 'Step 3 (Fails)', function($v) { throw new Exception('Intentional failure'); }));
$def3->addTask(new WorkflowTask('step4', 'Step 4', fn($v) => ['step4Done' => true]));

$def3->addFlow('start', 'step1');
$def3->addFlow('step1', 'step2');
$def3->addFlow('step2', 'step3_fail');
$def3->addFlow('step3_fail', 'step4');
$def3->addFlow('step4', 'end');

$instance3 = new WorkflowInstance('compensate-001', $def3);
$instance3->addCompensation('step1', function($v) { echo "  [Compensation] Undo Step 1\n"; });
$instance3->addCompensation('step2', function($v) { echo "  [Compensation] Undo Step 2\n"; });
$result3 = $instance3->execute();
echo "Status: {$result3['status']}\n";

echo "\n--- Sub-Process ---\n";
$subDef = new WorkflowDefinition();
$subDef->addTask(new WorkflowTask('sub1', 'Sub Task 1', fn($v) => ['subResult1' => 'ok']));
$subDef->addTask(new WorkflowTask('sub2', 'Sub Task 2', fn($v) => ['subResult2' => 'ok']));
$subDef->addFlow('start', 'sub1');
$subDef->addFlow('sub1', 'sub2');
$subDef->addFlow('sub2', 'end');

$mainDef = new WorkflowDefinition();
$mainDef->addTask(new WorkflowTask('main1', 'Main Task 1', fn($v) => ['mainResult1' => 'ok']));
$mainDef->addTask(new WorkflowTask('call_subprocess', 'Call Sub-Process', function($v) use ($subDef) {
    $sub = new SubProcess('sub-001', $subDef);
    $subResult = $sub->execute($v);
    return $subResult['variables'];
}));
$mainDef->addTask(new WorkflowTask('main2', 'Main Task 2', fn($v) => ['mainResult2' => 'ok']));
$mainDef->addFlow('start', 'main1');
$mainDef->addFlow('main1', 'call_subprocess');
$mainDef->addFlow('call_subprocess', 'main2');
$mainDef->addFlow('main2', 'end');

$instance4 = new WorkflowInstance('main-001', $mainDef, ['input' => 'test']);
$result4 = $instance4->execute();
echo "Status: {$result4['status']}\n";
echo "Variables: " . json_encode($result4['variables']) . "\n";

echo "\n--- Inclusive Gateway ---\n";
$def5 = new WorkflowDefinition();
$def5->addTask(new WorkflowTask('check', 'Check Conditions', fn($v) => ['gold' => $v['gold'] ?? false, 'silver' => $v['silver'] ?? false]));
$def5->addTask(new WorkflowTask('gold_reward', 'Gold Reward', fn($v) => ['goldGiven' => true]));
$def5->addTask(new WorkflowTask('silver_reward', 'Silver Reward', fn($v) => ['silverGiven' => true]));
$def5->addTask(new WorkflowTask('no_reward', 'No Reward', fn($v) => ['noReward' => true]));

$def5->addGateway(new Gateway('reward_gw', 'inclusive'));
$def5->addFlow('start', 'check');
$def5->addFlow('check', 'reward_gw');
$def5->addFlow('reward_gw', 'gold_reward', fn($v) => ($v['gold'] ?? false) === true);
$def5->addFlow('reward_gw', 'silver_reward', fn($v) => ($v['silver'] ?? false) === true);
$def5->addFlow('reward_gw', 'no_reward', fn($v) => !($v['gold'] ?? false) && !($v['silver'] ?? false));
$def5->addFlow('gold_reward', 'end');
$def5->addFlow('silver_reward', 'end');
$def5->addFlow('no_reward', 'end');

echo "Both gold and silver:\n";
$instance5 = new WorkflowInstance('inclusive-001', $def5, ['gold' => true, 'silver' => true]);
$r5 = $instance5->execute();
echo "  Results: " . json_encode($r5['results']) . "\n";

echo "Only gold:\n";
$instance6 = new WorkflowInstance('inclusive-002', $def5, ['gold' => true, 'silver' => false]);
$r6 = $instance6->execute();
echo "  Results: " . json_encode($r6['results']) . "\n";

echo "=== f147 Done ===\n";
