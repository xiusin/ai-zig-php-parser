<?php
// 极度混搭: 状态机 + 状态转换图 + 守卫条件 + 嵌套状态 + 历史
echo "=== f076: State Machine + Guards + Nested + History ===\n";

class State {
    public function __construct(
        public string $name,
        public array $substates = [],
        public ?string $parent = null,
        public bool $isFinal = false
    ) {}
}

class Transition {
    public function __construct(
        public string $from,
        public string $to,
        public string $event,
        public ?string $guard = null,
        public ?string $action = null
    ) {}
}

class StateMachine {
    private array $states = [];
    private array $transitions = [];
    private string $current;
    private array $history = [];
    private array $actions = [];
    private array $context = [];

    public function __construct(private string $name) {}

    public function addState(State $state): self {
        $this->states[$state->name] = $state;
        return $this;
    }

    public function addTransition(Transition $t): self {
        $this->transitions[] = $t;
        return $this;
    }

    public function start(string $state): self {
        $this->current = $state;
        $this->history[] = $state;
        return $this;
    }

    public function fire(string $event): bool {
        foreach ($this->transitions as $t) {
            if ($t->from === $this->current && $t->event === $event) {
                if ($t->guard !== null && !$this->evaluateGuard($t->guard)) {
                    $this->actions[] = "Guard failed: {$t->guard} for $event";
                    return false;
                }
                $oldState = $this->current;
                $this->current = $t->to;
                $this->history[] = $t->to;
                if ($t->action !== null) {
                    $this->actions[] = "Action: {$t->action} ({$oldState}→{$t->to})";
                    $this->executeAction($t->action);
                }
                return true;
            }
        }
        $this->actions[] = "No transition for event '$event' in state '$this->current'";
        return false;
    }

    private function evaluateGuard(string $guard): bool {
        if (preg_match('/^(\w+)\s*(>=|<=|>|<|==|!=)\s*(.+)$/', $guard, $m)) {
            $field = $m[1]; $op = $m[2]; $val = $m[3];
            $actual = $this->context[$field] ?? 0;
            $val = is_numeric($val) ? (float)$val : trim($val, '"\'');
            return match($op) {
                '>=' => $actual >= $val, '<=' => $actual <= $val,
                '>' => $actual > $val, '<' => $actual < $val,
                '==' => $actual == $val, '!=' => $actual != $val,
            };
        }
        return (bool)($this->context[$guard] ?? false);
    }

    private function executeAction(string $action): void {
        if (str_starts_with($action, 'set:')) {
            $parts = explode(':', $action, 3);
            $this->context[$parts[1]] = $parts[2];
        } elseif (str_starts_with($action, 'inc:')) {
            $field = substr($action, 4);
            $this->context[$field] = ($this->context[$field] ?? 0) + 1;
        } elseif (str_starts_with($action, 'dec:')) {
            $field = substr($action, 4);
            $this->context[$field] = ($this->context[$field] ?? 0) - 1;
        }
    }

    public function setContext(string $key, mixed $value): void { $this->context[$key] = $value; }
    public function getContext(): array { return $this->context; }
    public function getCurrent(): string { return $this->current; }
    public function getHistory(): array { return $this->history; }
    public function getActions(): array { return $this->actions; }
    public function isFinal(): bool { return $this->states[$this->current]->isFinal ?? false; }
}

// 测试1: 订单状态机
echo "--- Order State Machine ---\n";
$sm = new StateMachine('Order');
$sm->addState(new State('pending'))
   ->addState(new State('paid'))
   ->addState(new State('shipped'))
   ->addState(new State('delivered', isFinal: true))
   ->addState(new State('cancelled', isFinal: true))
   ->addState(new State('refunded', isFinal: true));

$sm->addTransition(new Transition('pending', 'paid', 'pay', guard: 'amount>0', action: 'set:paid_at:now'))
   ->addTransition(new Transition('pending', 'cancelled', 'cancel'))
   ->addTransition(new Transition('paid', 'shipped', 'ship', action: 'set:tracking:TR123'))
   ->addTransition(new Transition('paid', 'refunded', 'refund', guard: 'days<=30'))
   ->addTransition(new Transition('shipped', 'delivered', 'deliver'))
   ->addTransition(new Transition('shipped', 'refunded', 'return', guard: 'days<=14'));

$sm->setContext('amount', 100);
$sm->setContext('days', 5);
$sm->start('pending');

echo "Initial: " . $sm->getCurrent() . "\n";
echo "Fire 'pay': " . var_export($sm->fire('pay'), true) . " → " . $sm->getCurrent() . "\n";
echo "Fire 'ship': " . var_export($sm->fire('ship'), true) . " → " . $sm->getCurrent() . "\n";
echo "Fire 'deliver': " . var_export($sm->fire('deliver'), true) . " → " . $sm->getCurrent() . "\n";
echo "Is final: " . var_export($sm->isFinal(), true) . "\n";

echo "\nContext: " . json_encode($sm->getContext()) . "\n";
echo "History: " . implode(' → ', $sm->getHistory()) . "\n";

echo "\n--- Guard Failure ---\n";
$sm2 = new StateMachine('Order2');
$sm2->addState(new State('pending'))->addState(new State('paid'))->addState(new State('cancelled', isFinal: true));
$sm2->addTransition(new Transition('pending', 'paid', 'pay', guard: 'amount>0'));
$sm2->setContext('amount', 0);
$sm2->start('pending');
echo "Amount=0, fire 'pay': " . var_export($sm2->fire('pay'), true) . " (should fail)\n";
$sm2->setContext('amount', 50);
echo "Amount=50, fire 'pay': " . var_export($sm2->fire('pay'), true) . " → " . $sm2->getCurrent() . "\n";

echo "\n--- Vending Machine ---\n";
$vm = new StateMachine('Vending');
$vm->addState(new State('idle'))
   ->addState(new State('coin_inserted'))
   ->addState(new State('product_selected'))
   ->addState(new State('dispensing'))
   ->addState(new State('done', isFinal: true));

$vm->addTransition(new Transition('idle', 'coin_inserted', 'insert_coin', action: 'inc:balance'))
   ->addTransition(new Transition('coin_inserted', 'coin_inserted', 'insert_coin', action: 'inc:balance'))
   ->addTransition(new Transition('coin_inserted', 'product_selected', 'select', guard: 'balance>=price', action: 'dec:balance'))
   ->addTransition(new Transition('product_selected', 'dispensing', 'confirm'))
   ->addTransition(new Transition('dispensing', 'done', 'dispense'))
   ->addTransition(new Transition('coin_inserted', 'idle', 'refund', action: 'set:balance:0'));

$vm->setContext('balance', 0);
$vm->setContext('price', 3);
$vm->start('idle');

echo "Insert coin: " . var_export($vm->fire('insert_coin'), true) . " balance=" . $vm->getContext()['balance'] . "\n";
echo "Insert coin: " . var_export($vm->fire('insert_coin'), true) . " balance=" . $vm->getContext()['balance'] . "\n";
echo "Select (balance<price): " . var_export($vm->fire('select'), true) . "\n";
echo "Insert coin: " . var_export($vm->fire('insert_coin'), true) . " balance=" . $vm->getContext()['balance'] . "\n";
echo "Select: " . var_export($vm->fire('select'), true) . " → " . $vm->getCurrent() . "\n";
echo "Confirm: " . var_export($vm->fire('confirm'), true) . " → " . $vm->getCurrent() . "\n";
echo "Dispense: " . var_export($vm->fire('dispense'), true) . " → " . $vm->getCurrent() . "\n";

echo "\n--- Action Log ---\n";
foreach ($vm->getActions() as $a) echo "  $a\n";

echo "=== f076 Done ===\n";
