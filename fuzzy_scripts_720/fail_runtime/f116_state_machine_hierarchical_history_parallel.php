<?php
// 极度混搭: 状态机 + 状态层次 + 历史状态 + 并发状态
echo "=== f116: StateMachine + Hierarchical + History + Parallel ===\n";

class State {
    public array $substates = [];
    public array $transitions = [];
    public ?string $parent = null;
    public bool $isInitial = false;
    public bool $isFinal = false;
    public array $onEnter = [];
    public array $onExit = [];
    public array $history = []; // shallow history

    public function __construct(public string $id, public string $label = '') {}
}

class Transition {
    public $guard = null;
    public function __construct(
        public string $from,
        public string $to,
        public ?string $event = null,
        $guard = null,
        public array $actions = []
    ) {
        $this->guard = $guard;
    }
}

class HierarchicalStateMachine {
    public array $states = [];
    private string $currentState;
    private array $history = []; // region => state
    private array $activeStates = []; // parallel regions
    private array $log = [];

    public function addState(State $state): self {
        $this->states[$state->id] = $state;
        return $this;
    }

    public function addTransition(Transition $t): self {
        $this->states[$t->from]->transitions[] = $t;
        return $this;
    }

    public function setInitialState(string $stateId): void {
        $this->currentState = $stateId;
        $this->log[] = "Initial state: $stateId";
    }

    public function fireEvent(string $event, array $context = []): bool {
        $state = $this->states[$this->currentState];
        foreach ($state->transitions as $trans) {
            if ($trans->event !== $event) continue;
            if ($trans->guard !== null && !($trans->guard)($context)) {
                $this->log[] = "Guard blocked: $trans->from → $trans->to on '$event'";
                continue;
            }
            // 记录历史
            if ($state->parent !== null) {
                $this->history[$state->parent] = $this->currentState;
            }
            // exit actions
            foreach ($state->onExit as $action) { $this->log[] = "Exit $state->id: $action"; }
            // transition actions
            foreach ($trans->actions as $action) { $this->log[] = "Action: $action"; }
            $this->currentState = $trans->to;
            $newState = $this->states[$trans->to];
            foreach ($newState->onEnter as $action) { $this->log[] = "Enter $newState->id: $action"; }
            $this->log[] = "Transition: $trans->from → $trans->to (event='$event')";
            // 如果进入复合状态,进入其初始子状态
            $this->enterComposite($trans->to);
            return true;
        }
        // 检查父状态转换 (层次化)
        if (isset($state->parent)) {
            $parent = $this->states[$state->parent];
            foreach ($parent->transitions as $trans) {
                if ($trans->event !== $event) continue;
                if ($trans->guard !== null && !($trans->guard)($context)) continue;
                $this->history[$state->parent] = $this->currentState;
                foreach ($state->onExit as $a) $this->log[] = "Exit $state->id: $a";
                $this->currentState = $trans->to;
                $this->log[] = "Hierarchical transition: $trans->from → $trans->to (event='$event')";
                $this->enterComposite($trans->to);
                return true;
            }
        }
        $this->log[] = "No transition for event '$event' in state '$this->currentState'";
        return false;
    }

    private function enterComposite(string $stateId): void {
        $state = $this->states[$stateId];
        if (!empty($state->substates)) {
            foreach ($state->substates as $sub) {
                $subState = $this->states[$sub];
                if ($subState->isInitial) {
                    $this->currentState = $sub;
                    $this->log[] = "Enter initial substate: $sub";
                    $this->enterComposite($sub);
                    return;
                }
            }
        }
    }

    public function restoreHistory(string $compositeId): bool {
        if (isset($this->history[$compositeId])) {
            $this->currentState = $this->history[$compositeId];
            $this->log[] = "Restored history: $compositeId → $this->currentState";
            return true;
        }
        return false;
    }

    public function getCurrentState(): string { return $this->currentState; }
    public function getLog(): array { return $this->log; }
}

class ParallelStateMachine {
    private array $regions = [];
    private array $currentStates = [];

    public function addRegion(string $name, HierarchicalStateMachine $hsm): void {
        $this->regions[$name] = $hsm;
        $this->currentStates[$name] = $hsm->getCurrentState();
    }

    public function fireEvent(string $event, array $context = []): array {
        $results = [];
        foreach ($this->regions as $name => $hsm) {
            $results[$name] = $hsm->fireEvent($event, $context);
            $this->currentStates[$name] = $hsm->getCurrentState();
        }
        return $results;
    }

    public function getStates(): array { return $this->currentStates; }
}

// 测试
echo "--- Basic State Machine ---\n";
$hsm = new HierarchicalStateMachine();

$hsm->addState((function() { $s = new State('idle', 'Idle'); $s->isInitial = true; return $s; })());
$hsm->addState(new State('running', 'Running'));
$hsm->addState(new State('paused', 'Paused'));
$hsm->addState(new State('stopped', 'Stopped'));

$hsm->setInitialState('idle');
$hsm->addTransition(new Transition('idle', 'running', 'start', null, ['doStart()']));
$hsm->addTransition(new Transition('running', 'paused', 'pause', null, ['doPause()']));
$hsm->addTransition(new Transition('paused', 'running', 'resume', null, ['doResume()']));
$hsm->addTransition(new Transition('running', 'stopped', 'stop', null, ['doStop()']));
$hsm->addTransition(new Transition('paused', 'stopped', 'stop', null, ['doStop()']));
$hsm->addTransition(new Transition('stopped', 'idle', 'reset', null, ['doReset()']));

$events = ['start', 'pause', 'resume', 'pause', 'stop', 'reset', 'start'];
foreach ($events as $e) {
    $hsm->fireEvent($e);
    echo "  After '$e': state=" . $hsm->getCurrentState() . "\n";
}

echo "\n--- Guard Conditions ---\n";
$hsm2 = new HierarchicalStateMachine();
$hsm2->addState((function() { $s = new State('locked', 'Locked'); $s->isInitial = true; return $s; })());
$hsm2->addState(new State('unlocked', 'Unlocked'));
$hsm2->addState(new State('alarm', 'Alarm'));

$hsm2->setInitialState('locked');
$hsm2->addTransition(new Transition('locked', 'unlocked', 'coin', null, ['collectCoin()']));
$hsm2->addTransition(new Transition('unlocked', 'locked', 'push', null, ['lockGate()']));
$hsm2->addTransition(new Transition('locked', 'alarm', 'push', fn($ctx) => ($ctx['attempts'] ?? 0) >= 3, ['triggerAlarm()']));
$hsm2->addTransition(new Transition('alarm', 'locked', 'reset', null, ['clearAlarm()']));

echo "Turnstile with alarm (needs 3+ attempts to trigger alarm):\n";
$hsm2->fireEvent('push', ['attempts' => 1]); echo "  push(1): " . $hsm2->getCurrentState() . "\n";
$hsm2->fireEvent('push', ['attempts' => 3]); echo "  push(3): " . $hsm2->getCurrentState() . "\n";
$hsm2->fireEvent('reset'); echo "  reset: " . $hsm2->getCurrentState() . "\n";
$hsm2->fireEvent('coin'); echo "  coin: " . $hsm2->getCurrentState() . "\n";
$hsm2->fireEvent('push'); echo "  push: " . $hsm2->getCurrentState() . "\n";

echo "\n--- Hierarchical State Machine ---\n";
$hsm3 = new HierarchicalStateMachine();

// 顶层: operating
$hsm3->addState((function() { $s = new State('operating', 'Operating'); $s->isInitial = true; return $s; })());
// 子状态: active (初始), maintenance
$active = new State('active', 'Active');
$active->parent = 'operating';
$active->isInitial = true;
$hsm3->addState($active);

$maintenance = new State('maintenance', 'Maintenance');
$maintenance->parent = 'operating';
$hsm3->addState($maintenance);

// active 的子状态: idle (初始), processing
$idle = new State('idle', 'Idle');
$idle->parent = 'active';
$idle->isInitial = true;
$hsm3->addState($idle);

$processing = new State('processing', 'Processing');
$processing->parent = 'active';
$hsm3->addState($processing);

$hsm3->addState(new State('shutdown', 'Shutdown'));

// 设置子状态关系
$hsm3->states['operating']->substates = ['active', 'maintenance'];
$hsm3->states['active']->substates = ['idle', 'processing'];

$hsm3->setInitialState('operating');

$hsm3->addTransition(new Transition('idle', 'processing', 'task_start'));
$hsm3->addTransition(new Transition('processing', 'idle', 'task_done'));
$hsm3->addTransition(new Transition('active', 'maintenance', 'enter_maintenance'));
$hsm3->addTransition(new Transition('maintenance', 'active', 'exit_maintenance'));
$hsm3->addTransition(new Transition('operating', 'shutdown', 'power_off'));

echo "Current: " . $hsm3->getCurrentState() . "\n";
$hsm3->fireEvent('task_start'); echo "  task_start: " . $hsm3->getCurrentState() . "\n";
$hsm3->fireEvent('task_done'); echo "  task_done: " . $hsm3->getCurrentState() . "\n";
$hsm3->fireEvent('enter_maintenance'); echo "  enter_maintenance: " . $hsm3->getCurrentState() . "\n";
$hsm3->fireEvent('exit_maintenance'); echo "  exit_maintenance: " . $hsm3->getCurrentState() . "\n";
$hsm3->fireEvent('power_off'); echo "  power_off: " . $hsm3->getCurrentState() . "\n";

echo "\n--- Parallel Regions ---\n";
$region1 = new HierarchicalStateMachine();
$region1->addState((function() { $s = new State('on', 'On'); $s->isInitial = true; return $s; })());
$region1->addState(new State('off', 'Off'));
$region1->setInitialState('on');
$region1->addTransition(new Transition('on', 'off', 'toggle'));
$region1->addTransition(new Transition('off', 'on', 'toggle'));

$region2 = new HierarchicalStateMachine();
$region2->addState((function() { $s = new State('low', 'Low'); $s->isInitial = true; return $s; })());
$region2->addState(new State('high', 'High'));
$region2->setInitialState('low');
$region2->addTransition(new Transition('low', 'high', 'switch'));
$region2->addTransition(new Transition('high', 'low', 'switch'));

$parallel = new ParallelStateMachine();
$parallel->addRegion('power', $region1);
$parallel->addRegion('speed', $region2);

echo "Initial: " . json_encode($parallel->getStates()) . "\n";
$parallel->fireEvent('toggle');
echo "After toggle: " . json_encode($parallel->getStates()) . "\n";
$parallel->fireEvent('switch');
echo "After switch: " . json_encode($parallel->getStates()) . "\n";
$parallel->fireEvent('toggle');
echo "After toggle: " . json_encode($parallel->getStates()) . "\n";

echo "\n--- State Machine Log ---\n";
foreach (array_slice($hsm3->getLog(), -10) as $log) echo "  $log\n";

echo "=== f116 Done ===\n";
