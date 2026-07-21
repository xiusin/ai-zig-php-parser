<?php
// 极度混搭: 形式语言 + 自动机 + DFA最小化 + 正则等价
echo "=== f100: Automata + DFA Minimization + Regex Equiv ===\n";

class DFA {
    public array $states = [];
    public array $transitions = []; // [state][char] = state
    public array $acceptStates = [];
    public array $alphabet = [];

    public function __construct(array $states, array $alphabet, array $transitions, array $accept, string $start = 'q0') {
        $this->states = $states;
        $this->alphabet = $alphabet;
        $this->transitions = $transitions;
        $this->acceptStates = $accept;
        $this->startState = $start;
    }

    public function accepts(string $input): bool {
        $current = $this->startState;
        for ($i = 0; $i < strlen($input); $i++) {
            $char = $input[$i];
            if (!isset($this->transitions[$current][$char])) return false;
            $current = $this->transitions[$current][$char];
        }
        return in_array($current, $this->acceptStates);
    }

    public function minimize(): self {
        // Hopcroft 简化版
        $acceptStates = array_fill_keys($this->acceptStates, true);
        $nonAccept = array_fill_keys(array_diff($this->states, $this->acceptStates), true);

        $P = [];
        if (!empty($acceptStates)) $P[] = array_keys($acceptStates);
        if (!empty($nonAccept)) $P[] = array_keys($nonAccept);

        $changed = true;
        while ($changed) {
            $changed = false;
            $newP = [];
            foreach ($P as $group) {
                if (count($group) <= 1) { $newP[] = $group; continue; }
                // 尝试拆分
                $subgroups = [];
                foreach ($group as $state) {
                    $sig = '';
                    foreach ($this->alphabet as $char) {
                        $next = $this->transitions[$state][$char] ?? null;
                        $groupIdx = -1;
                        foreach ($P as $i => $g) {
                            if (in_array($next, $g)) { $groupIdx = $i; break; }
                        }
                        $sig .= "$char:$groupIdx;";
                    }
                    $subgroups[$sig][] = $state;
                }
                if (count($subgroups) > 1) $changed = true;
                foreach ($subgroups as $sub) $newP[] = $sub;
            }
            $P = $newP;
        }
        // 构建新DFA
        $newStates = [];
        $newTransitions = [];
        $newAccept = [];
        foreach ($P as $i => $group) {
            $stateName = "m$i";
            $newStates[] = $stateName;
            foreach ($group as $s) {
                if (in_array($s, $this->acceptStates)) { $newAccept[] = $stateName; break; }
            }
            foreach ($this->alphabet as $char) {
                $next = $this->transitions[$group[0]][$char] ?? null;
                if ($next !== null) {
                    foreach ($P as $j => $g) {
                        if (in_array($next, $g)) { $newTransitions[$stateName][$char] = "m$j"; break; }
                    }
                }
            }
        }
        return new self($newStates, $this->alphabet, $newTransitions, $newAccept);
    }

    public function getStateCount(): int { return count($this->states); }
    public function getAcceptStates(): array { return $this->acceptStates; }
    public function __toString(): string {
        $s = "States: " . implode(', ', $this->states) . "\n";
        $s .= "Accept: " . implode(', ', $this->acceptStates) . "\n";
        $s .= "Transitions:\n";
        foreach ($this->transitions as $state => $trans) {
            foreach ($trans as $char => $to) {
                $s .= "  $state --$char--> $to\n";
            }
        }
        return $s;
    }
}

class NFAtoDFA {
    public static function convert(NFA $nfa): DFA {
        // 简化: 只处理已确定的转换
        $states = [];
        $transitions = [];
        $accept = [];
        $alphabet = $nfa->alphabet;
        $startSet = $nfa->epsilonClosure([$nfa->start]);
        $startKey = implode(',', $startSet);
        $states[$startKey] = $startSet;
        if (array_intersect($startSet, $nfa->accept)) $accept[] = $startKey;

        $queue = [$startKey => $startSet];
        while (!empty($queue)) {
            $currentKey = array_key_first($queue);
            $currentSet = $queue[$currentKey];
            unset($queue[$currentKey]);

            foreach ($alphabet as $char) {
                $nextSet = [];
                foreach ($currentSet as $state) {
                    if (isset($nfa->transitions[$state][$char])) {
                        foreach ($nfa->transitions[$state][$char] as $t) $nextSet[] = $t;
                    }
                }
                $nextSet = $nfa->epsilonClosure($nextSet);
                if (empty($nextSet)) continue;
                $nextKey = implode(',', $nextSet);
                if (!isset($states[$nextKey])) {
                    $states[$nextKey] = $nextSet;
                    if (array_intersect($nextSet, $nfa->accept)) $accept[] = $nextKey;
                    $queue[$nextKey] = $nextSet;
                }
                $transitions[$currentKey][$char] = $nextKey;
            }
        }
        return new DFA(array_keys($states), $alphabet, $transitions, $accept, implode(',', $startSet));
    }
}

class NFA {
    public array $transitions = [];
    public array $epsilonTrans = [];
    public array $alphabet = [];

    public function __construct(public array $states, public string $start, public array $accept) {}

    public function addTransition(string $from, string $char, string $to): void {
        $this->transitions[$from][$char][] = $to;
        if (!in_array($char, $this->alphabet)) $this->alphabet[] = $char;
    }
    public function addEpsilon(string $from, string $to): void { $this->epsilonTrans[$from][] = $to; }

    public function epsilonClosure(array $states): array {
        $closure = []; $stack = $states;
        while (!empty($stack)) {
            $s = array_pop($stack);
            if (isset($closure[$s])) continue;
            $closure[$s] = true;
            if (isset($this->epsilonTrans[$s])) {
                foreach ($this->epsilonTrans[$s] as $e) $stack[] = $e;
            }
        }
        return array_keys($closure);
    }
}

// 测试
echo "--- DFA: Accepts strings ending in 'ab' ---\n";
$dfa = new DFA(
    ['q0', 'q1', 'q2'],
    ['a', 'b'],
    [
        'q0' => ['a' => 'q1', 'b' => 'q0'],
        'q1' => ['a' => 'q1', 'b' => 'q2'],
        'q2' => ['a' => 'q1', 'b' => 'q0'],
    ],
    ['q2']
);
echo $dfa;
$tests = ['ab', 'aab', 'bbab', 'ba', 'a', 'abab', 'baba', 'ababab'];
foreach ($tests as $t) {
    echo "  '$t' → " . var_export($dfa->accepts($t), true) . "\n";
}

echo "\n--- DFA: Accepts strings with even number of 'a' ---\n";
$dfa2 = new DFA(
    ['even', 'odd'],
    ['a', 'b'],
    [
        'even' => ['a' => 'odd', 'b' => 'even'],
        'odd' => ['a' => 'even', 'b' => 'odd'],
    ],
    ['even']
);
$tests2 = ['', 'a', 'aa', 'ab', 'aabb', 'abab', 'aaa'];
foreach ($tests2 as $t) {
    echo "  '$t' → " . var_export($dfa2->accepts($t), true) . "\n";
}

echo "\n--- DFA Minimization ---\n";
// 非最小DFA (有等价状态)
$nonMin = new DFA(
    ['q0', 'q1', 'q2', 'q3', 'q4'],
    ['a', 'b'],
    [
        'q0' => ['a' => 'q1', 'b' => 'q2'],
        'q1' => ['a' => 'q3', 'b' => 'q4'],
        'q2' => ['a' => 'q3', 'b' => 'q4'],
        'q3' => ['a' => 'q3', 'b' => 'q3'],
        'q4' => ['a' => 'q3', 'b' => 'q3'],
    ],
    ['q3', 'q4']
);
echo "Before minimization: " . $nonMin->getStateCount() . " states\n";
echo $nonMin;
$minimized = $nonMin->minimize();
echo "\nAfter minimization: " . $minimized->getStateCount() . " states\n";
echo $minimized;

echo "\n--- Verify minimized DFA accepts same language ---\n";
$verifyTests = ['', 'a', 'b', 'ab', 'ba', 'aa', 'bb', 'aba', 'bab'];
foreach ($verifyTests as $t) {
    $orig = $nonMin->accepts($t);
    $min = $minimized->accepts($t);
    $match = $orig === $min ? '✓' : '✗';
    echo "  '$t' → orig=" . var_export($orig, true) . " min=" . var_export($min, true) . " $match\n";
}

echo "\n--- NFA to DFA ---\n";
$nfa = new NFA(['n0', 'n1', 'n2'], 'n0', ['n2']);
$nfa->addTransition('n0', 'a', 'n0');
$nfa->addTransition('n0', 'b', 'n0');
$nfa->addTransition('n0', 'a', 'n1');
$nfa->addTransition('n1', 'b', 'n2');
echo "NFA (accepts strings ending in 'ab'):\n";
echo "States: " . implode(', ', $nfa->states) . "\n";
$convertedDfa = NFAtoDFA::convert($nfa);
echo "\nConverted DFA:\n";
echo "States: " . count($convertedDfa->states) . "\n";
echo $convertedDfa;

echo "\nVerify converted DFA:\n";
foreach ($tests as $t) {
    echo "  '$t' → " . var_export($convertedDfa->accepts($t), true) . "\n";
}

echo "=== f100 Done ===\n";
