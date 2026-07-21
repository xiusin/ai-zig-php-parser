<?php
// 极度混搭: 状态模式 + 订单状态机 + 转换规则 + 历史追踪 + 条件守卫
echo "=== f033: State Pattern + Order State Machine ===\n";

interface State {
    public function getName(): string;
    public function canTransitionTo(State $target): bool;
}

class OrderState implements State {
    public function __construct(private string $name, private array $allowedTransitions) {}

    public function getName(): string { return $this->name; }
    public function canTransitionTo(State $target): bool {
        return in_array($target->getName(), $this->allowedTransitions);
    }
}

class StateMachine {
    private array $states = [];
    private State $current;
    private array $history = [];
    private array $guards = [];

    public function addState(string $name, array $transitions = []): self {
        $this->states[$name] = new OrderState($name, $transitions);
        if (count($this->states) === 1) {
            $this->current = $this->states[$name];
            $this->history[] = ['state' => $name, 'action' => 'init'];
        }
        return $this;
    }

    public function addGuard(string $from, string $to, callable $guard): self {
        $key = "$from=>$to";
        $this->guards[$key][] = $guard;
        return $this;
    }

    public function transition(string $targetName, string $action = '', array $context = []): bool {
        if (!isset($this->states[$targetName])) return false;
        $target = $this->states[$targetName];
        if (!$this->current->canTransitionTo($target)) return false;

        $key = $this->current->getName() . "=>$targetName";
        if (isset($this->guards[$key])) {
            foreach ($this->guards[$key] as $guard) {
                if (!$guard($context)) return false;
            }
        }

        $this->current = $target;
        $this->history[] = ['state' => $targetName, 'action' => $action, 'context' => $context];
        return true;
    }

    public function getCurrentState(): string { return $this->current->getName(); }
    public function getHistory(): array { return $this->history; }
    public function can(string $target): bool {
        return isset($this->states[$target]) && $this->current->canTransitionTo($this->states[$target]);
    }
}

// 构建状态机
$sm = new StateMachine();
$sm->addState('pending', ['paid', 'cancelled'])
   ->addState('paid', ['processing', 'refunded'])
   ->addState('processing', ['shipped', 'refunded'])
   ->addState('shipped', ['delivered', 'returned'])
   ->addState('delivered', ['returned'])
   ->addState('refunded', [])
   ->addState('cancelled', [])
   ->addState('returned', []);

// 添加守卫
$sm->addGuard('pending', 'paid', fn($ctx) => ($ctx['amount'] ?? 0) > 0);
$sm->addGuard('processing', 'shipped', fn($ctx) => ($ctx['tracking'] ?? '') !== '');

// 测试
echo "Initial: " . $sm->getCurrentState() . "\n";

echo "\n--- Paid (amount=100) ---\n";
$ok = $sm->transition('paid', 'payment received', ['amount' => 100]);
echo "Transition: " . var_export($ok, true) . ", state=" . $sm->getCurrentState() . "\n";

echo "\n--- Try ship without tracking ---\n";
$sm->transition('processing', 'start processing');
$ok = $sm->transition('shipped', 'ship', ['tracking' => '']);
echo "Transition (no tracking): " . var_export($ok, true) . ", state=" . $sm->getCurrentState() . "\n";

echo "\n--- Ship with tracking ---\n";
$ok = $sm->transition('shipped', 'ship', ['tracking' => 'TRK123']);
echo "Transition: " . var_export($ok, true) . ", state=" . $sm->getCurrentState() . "\n";

echo "\n--- Deliver ---\n";
$ok = $sm->transition('delivered', 'delivered');
echo "Transition: " . var_export($ok, true) . ", state=" . $sm->getCurrentState() . "\n";

echo "\n--- Try invalid transition ---\n";
$ok = $sm->transition('pending', 'go back');
echo "Transition (invalid): " . var_export($ok, true) . "\n";

echo "\n--- Can checks ---\n";
echo "Can return: " . var_export($sm->can('returned'), true) . "\n";
echo "Can pending: " . var_export($sm->can('pending'), true) . "\n";

echo "\n--- History ---\n";
foreach ($sm->getHistory() as $h) {
    echo "  {$h['state']}: {$h['action']}\n";
}

echo "=== f033 Done ===\n";
