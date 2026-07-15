<?php
// 极度混搭: 工作流引擎 + 状态转换 + 条件分支 + 并行网关 + 回滚
echo "=== c044: Workflow Engine + StateTransition + Gateway + Rollback ===\n\n";

class WorkflowState {
    public string $name;
    public bool $isFinal;
    public bool $isInitial;
    public array $onEnter = [];
    public array $onExit = [];

    public function __construct(string $name, bool $isInitial = false, bool $isFinal = false) {
        $this->name = $name;
        $this->isInitial = $isInitial;
        $this->isFinal = $isFinal;
    }
}

class WorkflowTransition {
    public string $from;
    public string $to;
    public $condition;
    public string $name;

    public function __construct(string $name, string $from, string $to, ?callable $condition = null) {
        $this->name = $name;
        $this->from = $from;
        $this->to = $to;
        $this->condition = $condition;
    }

    public function canTransition(array $context): bool {
        if ($this->condition === null) return true;
        return ($this->condition)($context);
    }
}

class WorkflowInstance {
    public string $id;
    public string $currentState;
    public array $context;
    public array $history = [];
    public array $variables = [];
    public int $stepCount = 0;
    public bool $completed = false;
    public bool $cancelled = false;

    public function __construct(string $id, string $initialState, array $context = []) {
        $this->id = $id;
        $this->currentState = $initialState;
        $this->context = $context;
        $this->history[] = ['step' => 0, 'action' => 'start', 'from' => '', 'to' => $initialState];
    }

    public function recordTransition(string $action, string $from, string $to): void {
        $this->stepCount++;
        $this->history[] = [
            'step' => $this->stepCount,
            'action' => $action,
            'from' => $from,
            'to' => $to,
        ];
        $this->currentState = $to;
    }

    public function getHistory(): array {
        return $this->history;
    }

    public function setVar(string $key, mixed $value): void {
        $this->variables[$key] = $value;
    }

    public function getVar(string $key): mixed {
        return $this->variables[$key] ?? null;
    }
}

class WorkflowEngine {
    private array $states = [];
    private array $transitions = [];
    private array $instances = [];

    public function addState(WorkflowState $state): self {
        $this->states[$state->name] = $state;
        return $this;
    }

    public function addTransition(WorkflowTransition $transition): self {
        $this->transitions[$transition->from][] = $transition;
        return $this;
    }

    public function start(string $instanceId, array $context = []): WorkflowInstance {
        $initial = null;
        foreach ($this->states as $state) {
            if ($state->isInitial) {
                $initial = $state->name;
                break;
            }
        }
        if ($initial === null) throw new RuntimeException("No initial state");

        $instance = new WorkflowInstance($instanceId, $initial, $context);
        $this->instances[$instanceId] = $instance;
        return $instance;
    }

    public function fire(string $instanceId, string $eventName, array $extra = []): bool {
        $instance = $this->instances[$instanceId] ?? null;
        if ($instance === null || $instance->completed || $instance->cancelled) return false;

        $transitions = $this->transitions[$instance->currentState] ?? [];
        foreach ($transitions as $t) {
            if ($t->name === $eventName) {
                $context = array_merge($instance->context, $instance->variables, $extra);
                if ($t->canTransition($context)) {
                    $oldState = $instance->currentState;
                    $instance->recordTransition($eventName, $oldState, $t->to);
                    $state = $this->states[$t->to] ?? null;
                    if ($state !== null && $state->isFinal) {
                        $instance->completed = true;
                    }
                    return true;
                }
            }
        }
        return false;
    }

    public function fireAll(string $instanceId): array {
        $instance = $this->instances[$instanceId] ?? null;
        if ($instance === null) return [];

        $fired = [];
        $transitions = $this->transitions[$instance->currentState] ?? [];
        foreach ($transitions as $t) {
            $context = array_merge($instance->context, $instance->variables);
            if ($t->canTransition($context)) {
                $this->fire($instanceId, $t->name);
                $fired[] = $t->name;
            }
        }
        return $fired;
    }

    public function rollback(string $instanceId, int $toStep): bool {
        $instance = $this->instances[$instanceId] ?? null;
        if ($instance === null) return false;

        $newHistory = [];
        $newState = null;
        foreach ($instance->history as $entry) {
            $newHistory[] = $entry;
            if ($entry['step'] == $toStep) {
                $newState = $entry['to'] ?? $entry['state'] ?? null;
                break;
            }
        }

        if ($newState === null) return false;
        $instance->history = $newHistory;
        $instance->currentState = $newState;
        $instance->completed = false;
        $instance->stepCount = $toStep;
        return true;
    }

    public function getInstance(string $instanceId): ?WorkflowInstance {
        return $this->instances[$instanceId] ?? null;
    }

    public function getState(): string { return ''; }
}

// === 测试：订单审批流程 ===

echo "--- Order Approval Workflow ---\n";
$engine = new WorkflowEngine();

// States
$engine->addState(new WorkflowState('created', true, false));
$engine->addState(new WorkflowState('pending_approval', false, false));
$engine->addState(new WorkflowState('approved', false, false));
$engine->addState(new WorkflowState('rejected', false, true));
$engine->addState(new WorkflowState('shipped', false, false));
$engine->addState(new WorkflowState('delivered', false, true));
$engine->addState(new WorkflowState('cancelled', false, true));

// Transitions
$engine->addTransition(new WorkflowTransition('submit', 'created', 'pending_approval'));
$engine->addTransition(new WorkflowTransition('approve', 'pending_approval', 'approved', fn($ctx) => ($ctx['amount'] ?? 0) <= 1000));
$engine->addTransition(new WorkflowTransition('reject', 'pending_approval', 'rejected'));
$engine->addTransition(new WorkflowTransition('escalate', 'pending_approval', 'pending_approval', fn($ctx) => ($ctx['amount'] ?? 0) > 1000));
$engine->addTransition(new WorkflowTransition('force_approve', 'pending_approval', 'approved', fn($ctx) => ($ctx['manager_override'] ?? false) === true));
$engine->addTransition(new WorkflowTransition('ship', 'approved', 'shipped'));
$engine->addTransition(new WorkflowTransition('deliver', 'shipped', 'delivered'));
$engine->addTransition(new WorkflowTransition('cancel', 'created', 'cancelled'));
$engine->addTransition(new WorkflowTransition('cancel', 'pending_approval', 'cancelled'));

// Start workflow
$instance = $engine->start('order-001', ['amount' => 500, 'customer' => 'Alice']);
echo "Started: {$instance->id} state={$instance->currentState}\n";

$engine->fire('order-001', 'submit');
echo "After submit: {$instance->currentState}\n";

$engine->fire('order-001', 'approve');
echo "After approve: {$instance->currentState} completed=" . var_export($instance->completed, true) . "\n";

$engine->fire('order-001', 'ship');
echo "After ship: {$instance->currentState}\n";

$engine->fire('order-001', 'deliver');
echo "After deliver: {$instance->currentState} completed=" . var_export($instance->completed, true) . "\n";

echo "\n--- High Amount (escalation) ---\n";
$instance2 = $engine->start('order-002', ['amount' => 5000, 'customer' => 'Bob']);
$engine->fire('order-002', 'submit');
echo "After submit: {$instance2->currentState}\n";
$canApprove = $engine->fire('order-002', 'approve');
echo "Approve (amount=5000): " . var_export($canApprove, true) . "\n";
$escalate = $engine->fire('order-002', 'escalate');
echo "Escalate: " . var_export($escalate, true) . "\n";

$instance2->setVar('manager_override', true);
$forceApprove = $engine->fire('order-002', 'force_approve');
echo "Force approve (override): " . var_export($forceApprove, true) . " state={$instance2->currentState}\n";

echo "\n--- Rejection ---\n";
$instance3 = $engine->start('order-003', ['amount' => 200, 'customer' => 'Charlie']);
$engine->fire('order-003', 'submit');
$engine->fire('order-003', 'reject');
echo "After reject: {$instance3->currentState} completed=" . var_export($instance3->completed, true) . "\n";

echo "\n--- Cancellation ---\n";
$instance4 = $engine->start('order-004', ['amount' => 100, 'customer' => 'Diana']);
$engine->fire('order-004', 'cancel');
echo "After cancel: {$instance4->currentState} completed=" . var_export($instance4->completed, true) . "\n";

echo "\n--- Rollback ---\n";
$instance5 = $engine->start('order-005', ['amount' => 300]);
$engine->fire('order-005', 'submit');
$engine->fire('order-005', 'approve');
echo "Before rollback: state={$instance5->currentState}\n";
$engine->rollback('order-005', 0);
echo "After rollback to step 0: state={$instance5->currentState}\n";
$engine->fire('order-005', 'cancel');
echo "After cancel: state={$instance5->currentState}\n";

echo "\n--- History ---\n";
foreach ($instance->getHistory() as $h) {
    echo "  Step {$h['step']}: {$h['action']} -> {$h['to']}\n";
}

echo "\n=== c044 Done ===\n";
