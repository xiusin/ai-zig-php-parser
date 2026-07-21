<?php
// 极度混搭: 形式化验证 + 模型检查 + 不变量 + 断言 + 模糊测试
echo "=== f146: Formal Verification + Model Check + Invariant + Fuzz ===\n";

class State {
    public function __construct(public string $label, public array $variables = []) {}
    public function get(string $name): mixed { return $this->variables[$name] ?? null; }
    public function set(string $name, mixed $value): void { $this->variables[$name] = $value; }
    public function equals(State $other): bool { return $this->label === $other->label && $this->variables == $other->variables; }
    public function __toString(): string { return "$this->label" . json_encode($this->variables); }
}

class Transition2 {
    public function __construct(public string $from, public string $to, public string $event, public $guard = null, public $action = null) {}
}

class ModelChecker {
    private array $states = [];
    private array $transitions = [];
    private array $invariants = [];

    public function addState(State $state): void { $this->states[$state->label] = $state; }
    public function addTransition(Transition2 $t): void { $this->transitions[] = $t; }
    public function addInvariant(string $name, callable $check): void { $this->invariants[$name] = $check; }

    public function checkInvariants(State $state): array {
        $violations = [];
        foreach ($this->invariants as $name => $check) {
            if (!$check($state)) $violations[] = $name;
        }
        return $violations;
    }

    public function checkAllStates(): array {
        $results = [];
        foreach ($this->states as $label => $state) {
            $violations = $this->checkInvariants($state);
            if (!empty($violations)) $results[$label] = $violations;
        }
        return $results;
    }

    public function verifyLTL(string $startState, callable $property, int $maxDepth = 100): array {
        $visited = [];
        $counterexamples = [];
        $this->exploreState($startState, [], $visited, $property, $counterexamples, $maxDepth);
        return $counterexamples;
    }

    private function exploreState(string $current, array $path, array &$visited, callable $property, array &$counterexamples, int $depth): void {
        if ($depth <= 0 || isset($visited[$current . implode('', $path)])) return;
        $visited[$current . implode('', $path)] = true;
        $state = $this->states[$current];
        if (!$property($state, $path)) {
            $counterexamples[] = ['path' => array_merge($path, [$current]), 'state' => $state];
            return;
        }
        $newPath = array_merge($path, [$current]);
        foreach ($this->transitions as $t) {
            if ($t->from !== $current) continue;
            $canTransition = $t->guard === null || ($t->guard)($state);
            if ($canTransition) $this->exploreState($t->to, $newPath, $visited, $property, $counterexamples, $depth - 1);
        }
    }

    public function deadStates(): array {
        $hasIncoming = [];
        foreach ($this->transitions as $t) $hasIncoming[$t->to] = true;
        $dead = [];
        foreach ($this->states as $label => $state) {
            if (!isset($hasIncoming[$label]) && $label !== array_key_first($this->states)) $dead[] = $label;
        }
        return $dead;
    }
}

class Fuzzer {
    private array $results = [];
    private int $crashes = 0;
    private int $timeouts = 0;
    private int $passed = 0;

    public function fuzz(callable $target, int $iterations = 1000, array $generators = []): array {
        for ($i = 0; $i < $iterations; $i++) {
            $input = $this->generateInput($generators);
            $start = microtime(true);
            try {
                $result = $target($input);
                $this->passed++;
                if ($result !== null) $this->results['interesting'][] = ['input' => $input, 'result' => $result, 'iteration' => $i];
            } catch (InvalidArgumentException $e) {
                $this->results['validation_errors'][] = ['input' => $input, 'error' => $e->getMessage(), 'iteration' => $i];
            } catch (Exception $e) {
                $this->crashes++;
                $this->results['crashes'][] = ['input' => $input, 'error' => $e->getMessage(), 'iteration' => $i];
            }
            if (microtime(true) - $start > 1.0) $this->timeouts++;
        }
        return $this->getStats();
    }

    private function generateInput(array $generators): array {
        $input = [];
        foreach ($generators as $name => $generator) {
            $input[$name] = $generator();
        }
        return $input;
    }

    public function getStats(): array {
        return [
            'iterations' => $this->passed + $this->crashes + $this->timeouts,
            'passed' => $this->passed,
            'crashes' => $this->crashes,
            'timeouts' => $this->timeouts,
            'interesting' => count($this->results['interesting'] ?? []),
        ];
    }

    public function getCrashes(): array { return $this->results['crashes'] ?? []; }

    public static function genInt(int $min = -1000, int $max = 1000): callable { return fn() => mt_rand($min, $max); }
    public static function genString(int $maxLen = 100): callable {
        return function() {
            $len = mt_rand(0, $maxLen);
            $chars = 'abcdefghijklmnopqrstuvwxyz0123456789!@#$%^&*()';
            $s = '';
            for ($i = 0; $i < $len; $i++) $s .= $chars[mt_rand(0, strlen($chars) - 1)];
            return $s;
        };
    }
    public static function genFloat(float $min = -100, float $max = 100): callable { return fn() => mt_rand() / mt_getrandmax() * ($max - $min) + $min; }
    public static function genArray(callable $elemGen, int $maxLen = 10): callable {
        return function() use ($elemGen, $maxLen) {
            $len = mt_rand(0, $maxLen);
            $arr = [];
            for ($i = 0; $i < $len; $i++) $arr[] = $elemGen();
            return $arr;
        };
    }
    public static function genBool(): callable { return fn() => mt_rand(0, 1) === 1; }
}

class AssertionChecker {
    public static function checkPreconditions(callable $fn, array $preconditions, array $args): array {
        foreach ($preconditions as $name => $check) {
            if (!$check($args)) return ['valid' => false, 'violated' => $name];
        }
        return ['valid' => true];
    }

    public static function checkPostconditions(callable $fn, array $postconditions, array $args, mixed $result): array {
        foreach ($postconditions as $name => $check) {
            if (!$check($args, $result)) return ['valid' => false, 'violated' => $name];
        }
        return ['valid' => true];
    }

    public static function checkLoopInvariant(callable $invariant, array $state): bool {
        return $invariant($state);
    }
}

// 测试
echo "--- Model Checking: Vending Machine ---\n";
$mc = new ModelChecker();

$mc->addState(new State('idle', ['credit' => 0, 'selected' => null]));
$mc->addState(new State('coin_inserted', ['credit' => 0, 'selected' => null]));
$mc->addState(new State('item_selected', ['credit' => 0, 'selected' => null]));
$mc->addState(new State('dispensing', ['credit' => 0, 'selected' => null]));
$mc->addState(new State('refund', ['credit' => 0, 'selected' => null]));

$mc->addTransition(new Transition2('idle', 'coin_inserted', 'insert_coin'));
$mc->addTransition(new Transition2('coin_inserted', 'coin_inserted', 'insert_coin'));
$mc->addTransition(new Transition2('coin_inserted', 'item_selected', 'select_item', fn($s) => $s->get('credit') >= 1));
$mc->addTransition(new Transition2('item_selected', 'dispensing', 'confirm'));
$mc->addTransition(new Transition2('dispensing', 'idle', 'dispense_complete'));
$mc->addTransition(new Transition2('coin_inserted', 'refund', 'cancel'));
$mc->addTransition(new Transition2('item_selected', 'refund', 'cancel'));
$mc->addTransition(new Transition2('refund', 'idle', 'refund_complete'));

$mc->addInvariant('non_negative_credit', fn($s) => ($s->get('credit') ?? 0) >= 0);
$mc->addInvariant('valid_state', fn($s) => in_array($s->label, ['idle', 'coin_inserted', 'item_selected', 'dispensing', 'refund']));

echo "Invariant violations: " . json_encode($mc->checkAllStates()) . "\n";
echo "Dead states: " . json_encode($mc->deadStates()) . "\n";

$ltlResult = $mc->verifyLTL('idle', fn($state, $path) => true, 10);
echo "LTL violations: " . count($ltlResult) . "\n";

echo "\n--- Model Checking: Bank Account ---\n";
$mc2 = new ModelChecker();
$mc2->addState(new State('open', ['balance' => 100]));
$mc2->addState(new State('open', ['balance' => 50]));
$mc2->addState(new State('open', ['balance' => 0]));
$mc2->addState(new State('frozen', ['balance' => 0]));

$mc2->addInvariant('non_negative_balance', fn($s) => ($s->get('balance') ?? 0) >= 0);
$mc2->addInvariant('frozen_zero', fn($s) => $s->label !== 'frozen' || ($s->get('balance') ?? -1) === 0);

$violations = $mc2->checkAllStates();
echo "Invariant violations: " . (empty($violations) ? 'none' : json_encode($violations)) . "\n";

echo "\n--- Fuzz Testing ---\n";
// 测试目标: 整数除法函数
$divide = function(array $input) {
    $a = $input['a'] ?? 0; $b = $input['b'] ?? 1;
    if ($b === 0) throw new InvalidArgumentException('Division by zero');
    return $a / $b;
};

$fuzzer = new Fuzzer();
$gen = [
    'a' => Fuzzer::genInt(-100, 100),
    'b' => Fuzzer::genInt(-10, 10),
];
$stats = $fuzzer->fuzz($divide, 500, $gen);
echo "Fuzz stats: " . json_encode($stats) . "\n";
$crashes = $fuzzer->getCrashes();
echo "Crashes: " . count($crashes) . "\n";

echo "\n--- Fuzz String Parser ---\n";
$parser = function(array $input) {
    $s = $input['text'] ?? '';
    if (strlen($s) > 200) throw new InvalidArgumentException('String too long');
    if (!preg_match('/^[a-zA-Z0-9\s]*$/', $s)) throw new InvalidArgumentException('Invalid characters');
    $words = explode(' ', $s);
    $words = array_filter($words, fn($w) => strlen($w) > 0);
    return ['word_count' => count($words), 'char_count' => strlen($s)];
};

$fuzzer2 = new Fuzzer();
$gen2 = ['text' => Fuzzer::genString(50)];
$stats2 = $fuzzer2->fuzz($parser, 300, $gen2);
echo "Fuzz stats: " . json_encode($stats2) . "\n";

echo "\n--- Precondition/Postcondition Checking ---\n";
$sortArray = function(array $arr) {
    if (empty($arr)) return [];
    sort($arr);
    return $arr;
};

$preconditions = [
    'all_numeric' => fn($args) => array_reduce($args[0] ?? [], fn($carry, $item) => $carry && is_numeric($item), true),
];

$postconditions = [
    'is_sorted' => fn($args, $result) => $result === array_values(array_filter($result, fn($v, $i) => $i === 0 || $result[$i - 1] <= $v, ARRAY_FILTER_USE_BOTH)),
    'same_length' => fn($args, $result) => count($result) === count($args[0] ?? []),
];

$testArrays = [[3, 1, 4, 1, 5, 9, 2, 6], [1], [], [5, 4, 3, 2, 1]];
foreach ($testArrays as $arr) {
    $preCheck = AssertionChecker::checkPreconditions($sortArray, $preconditions, [$arr]);
    if (!$preCheck['valid']) { echo "  Precondition violated: {$preCheck['violated']}\n"; continue; }
    $result = $sortArray($arr);
    $postCheck = AssertionChecker::checkPostconditions($sortArray, $postconditions, [$arr], $result);
    echo "  Input: [" . implode(',', $arr) . "] → [" . implode(',', $result) . "] PostCheck: " . var_export($postCheck['valid'], true) . "\n";
}

echo "\n--- Loop Invariant ---\n";
$factorial = function(int $n) {
    $result = 1;
    $i = 1;
    $invariant = fn($state) => $state['result'] >= 1 && $state['i'] >= 1 && $state['i'] <= $state['n'] + 1;
    while ($i <= $n) {
        $result *= $i;
        $i++;
        if (!AssertionChecker::checkLoopInvariant($invariant, ['result' => $result, 'i' => $i, 'n' => $n])) {
            echo "  Invariant violated at i=$i\n"; break;
        }
    }
    return $result;
};
echo "  factorial(5) = " . $factorial(5) . "\n";
echo "  factorial(10) = " . $factorial(10) . "\n";

echo "=== f146 Done ===\n";
