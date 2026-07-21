<?php
// 状态机：有限状态自动机、DFA/NFA 模拟、状态转换图
echo "=== f171: State Machine + DFA + NFA ===\n";

class StateMachine {
    private array $states = [];
    private array $transitions = [];
    private string $current;
    private string $initial;
    private array $finalStates = [];
    private array $history = [];
    private array $actions = [];

    public function __construct(string $initial) {
        $this->initial = $initial;
        $this->current = $initial;
        $this->states[$initial] = true;
    }

    public function addState(string $name): self {
        $this->states[$name] = true;
        return $this;
    }

    public function addFinalState(string $name): self {
        $this->states[$name] = true;
        $this->finalStates[$name] = true;
        return $this;
    }

    public function addTransition(string $from, string $input, string $to, ?callable $action = null): self {
        if (!isset($this->transitions[$from])) $this->transitions[$from] = [];
        $this->transitions[$from][$input] = ['to' => $to, 'action' => $action];
        return $this;
    }

    public function onEnter(string $state, callable $action): self {
        $this->actions[$state] = $action;
        return $this;
    }

    public function transition(string $input): bool {
        $this->history[] = ['state' => $this->current, 'input' => $input];
        if (!isset($this->transitions[$this->current][$input])) {
            echo "  [ERROR] No transition from {$this->current} on input '$input'\n";
            return false;
        }
        $transition = $this->transitions[$this->current][$input];
        $this->current = $transition['to'];
        if ($transition['action']) ($transition['action'])();
        if (isset($this->actions[$this->current])) ($this->actions[$this->current])();
        return true;
    }

    public function canTransition(string $input): bool {
        return isset($this->transitions[$this->current][$input]);
    }

    public function getCurrentState(): string { return $this->current; }
    public function isFinal(): bool { return isset($this->finalStates[$this->current]); }
    public function reset(): void { $this->current = $this->initial; $this->history = []; }
    public function getHistory(): array { return $this->history; }
    public function getAvailableInputs(): array {
        return array_keys($this->transitions[$this->current] ?? []);
    }
}

// DFA 字符串匹配
class DfaMatcher {
    private array $states = [];
    private string $start;
    private array $accept = [];

    public function __construct(string $start) { $this->start = $start; }

    public function addTransition(string $from, string $symbol, string $to): self {
        if (!isset($this->states[$from])) $this->states[$from] = [];
        $this->states[$from][$symbol] = $to;
        return $this;
    }

    public function addAccept(string $state): self {
        $this->accept[$state] = true;
        return $this;
    }

    public function match(string $input): bool {
        $current = $this->start;
        for ($i = 0; $i < strlen($input); $i++) {
            $symbol = $input[$i];
            if (!isset($this->states[$current][$symbol])) return false;
            $current = $this->states[$current][$symbol];
        }
        return isset($this->accept[$current]);
    }
}

// 订单状态机
function buildOrderStateMachine(): StateMachine {
    $sm = new StateMachine('pending');
    $sm->addState('pending')
       ->addState('paid')
       ->addState('processing')
       ->addState('shipped')
       ->addState('delivered')
       ->addFinalState('delivered')
       ->addFinalState('cancelled')
       ->addFinalState('refunded');

    $sm->addTransition('pending', 'pay', 'paid', fn() => print("  → Payment received\n"))
       ->addTransition('pending', 'cancel', 'cancelled', fn() => print("  → Order cancelled\n"))
       ->addTransition('paid', 'process', 'processing', fn() => print("  → Processing order\n"))
       ->addTransition('paid', 'refund', 'refunded', fn() => print("  → Order refunded\n"))
       ->addTransition('processing', 'ship', 'shipped', fn() => print("  → Order shipped\n"))
       ->addTransition('processing', 'cancel', 'cancelled', fn() => print("  → Order cancelled during processing\n"))
       ->addTransition('shipped', 'deliver', 'delivered', fn() => print("  → Order delivered\n"))
       ->addTransition('shipped', 'return', 'refunded', fn() => print("  → Order returned and refunded\n"))
       ->addTransition('delivered', 'return', 'refunded', fn() => print("  → Post-delivery return\n"));

    return $sm;
}

// 测试
echo "--- Order State Machine ---\n";
$sm = buildOrderStateMachine();
echo "  Initial: {$sm->getCurrentState()}\n";
echo "  Available: " . implode(', ', $sm->getAvailableInputs()) . "\n";

echo "\n  Happy path:\n";
$sm->transition('pay');
$sm->transition('process');
$sm->transition('ship');
$sm->transition('deliver');
echo "  Final state: {$sm->getCurrentState()} (isFinal: " . ($sm->isFinal() ? 'Y' : 'N') . ")\n";

echo "\n  Cancel path:\n";
$sm->reset();
$sm->transition('pay');
$sm->transition('refund');
echo "  Final state: {$sm->getCurrentState()}\n";

echo "\n  Invalid transition:\n";
$sm->reset();
$sm->transition('ship'); // Should fail - can't ship from pending

echo "\n--- DFA: Match strings ending in 'ab' ---\n";
$dfa = new DfaMatcher('s0');
$dfa->addTransition('s0', 'a', 's1')
    ->addTransition('s0', 'b', 's0')
    ->addTransition('s1', 'a', 's1')
    ->addTransition('s1', 'b', 's2')
    ->addTransition('s2', 'a', 's1')
    ->addTransition('s2', 'b', 's0')
    ->addAccept('s2');

$tests = ['ab', 'aab', 'bab', 'baab', 'aabb', 'abab', 'aaa', 'bba', 'ababab', ''];
foreach ($tests as $test) {
    $match = $dfa->match($test);
    echo "  '$test': " . ($match ? 'ACCEPT' : 'REJECT') . "\n";
}

echo "\n--- DFA: Match binary numbers divisible by 3 ---\n";
$dfa2 = new DfaMatcher('r0'); // r0=rem 0, r1=rem 1, r2=rem 2
$dfa2->addTransition('r0', '0', 'r0')
     ->addTransition('r0', '1', 'r1')
     ->addTransition('r1', '0', 'r2')
     ->addTransition('r1', '1', 'r0')
     ->addTransition('r2', '0', 'r1')
     ->addTransition('r2', '1', 'r2')
     ->addAccept('r0');

$binTests = ['0', '1', '10', '11', '100', '110', '1001', '1100', '1111', '10010', '110', '0', '11', '110'];
foreach ($binTests as $bin) {
    $dec = bindec($bin);
    $match = $dfa2->match($bin);
    echo "  $bin (= $dec): " . ($match ? 'div by 3' : 'NOT div by 3') . " (actual: " . ($dec % 3 === 0 ? 'div by 3' : 'NOT div by 3') . ")\n";
}

echo "\n--- State History ---\n";
$sm2 = buildOrderStateMachine();
$sm2->transition('pay');
$sm2->transition('process');
$sm2->transition('ship');
echo "  History:\n";
foreach ($sm2->getHistory() as $h) {
    echo "    {$h['state']} --{$h['input']}--> \n";
}
echo "  Current: {$sm2->getCurrentState()}\n";

echo "=== f171 Done ===\n";
