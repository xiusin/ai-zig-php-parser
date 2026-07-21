<?php
// 极度混搭: 正则引擎 + NFA + 回溯 + 捕获组 + 反向引用
echo "=== f129: Regex Engine + NFA + Backtrack + Capture + Backref ===\n";

class RegexState {
    public array $transitions = []; // char => [states]
    public array $epsilonTrans = [];
    public function __construct(public int $id) {}
}

class RegexNFA {
    private int $stateCount = 0;
    public RegexState $start;
    public RegexState $accept;
    public array $captures = [];
    private array $captureGroups = [];

    public function __construct() {
        $this->start = new RegexState($this->stateCount++);
        $this->accept = new RegexState($this->stateCount++);
    }

    public function newState(): RegexState { return new RegexState($this->stateCount++); }

    public function addChar(RegexState $from, string $char, RegexState $to): void {
        $from->transitions[$char][] = $to;
    }

    public function addEpsilon(RegexState $from, RegexState $to): void {
        $from->epsilonTrans[] = $to;
    }

    public function epsilonClosure(array $states): array {
        $closure = []; $stack = $states;
        while (!empty($stack)) {
            $s = array_pop($stack);
            $id = $s->id;
            if (isset($closure[$id])) continue;
            $closure[$id] = $s;
            foreach ($s->epsilonTrans as $e) if (!isset($closure[$e->id])) $stack[] = $e;
        }
        return array_values($closure);
    }

    public function match(string $input): array {
        $current = $this->epsilonClosure([$this->start]);
        $this->captures = [];
        for ($i = 0; $i < strlen($input); $i++) {
            $char = $input[$i];
            $next = [];
            foreach ($current as $state) {
                if (isset($state->transitions[$char])) {
                    foreach ($state->transitions[$char] as $t) $next[] = $t;
                }
                if (isset($state->transitions['.'])) {
                    foreach ($state->transitions['.'] as $t) $next[] = $t;
                }
            }
            $current = $this->epsilonClosure($next);
            if (empty($current)) return ['match' => false, 'pos' => $i];
        }
        foreach ($current as $state) {
            if ($state->id === $this->accept->id) return ['match' => true, 'length' => strlen($input)];
        }
        return ['match' => false, 'pos' => strlen($input)];
    }
}

class RegexBuilder {
    public static function build(string $pattern): RegexNFA {
        $nfa = new RegexNFA();
        $pos = 0;
        $endState = self::parsePattern($pattern, $pos, $nfa, $nfa->start);
        $nfa->addEpsilon($endState, $nfa->accept);
        return $nfa;
    }

    private static function parsePattern(string $pattern, int &$pos, RegexNFA $nfa, RegexState $start): RegexState {
        $current = $start;
        while ($pos < strlen($pattern)) {
            $char = $pattern[$pos];
            if ($char === ')') return $current;
            if ($char === '|') { $pos++; $current = $start; continue; }
            if ($char === '(') {
                $pos++;
                $groupStart = $nfa->newState();
                $nfa->addEpsilon($current, $groupStart);
                $groupEnd = self::parsePattern($pattern, $pos, $nfa, $groupStart);
                $current = $groupEnd;
                $pos++;
                continue;
            }
            if ($char === '*' || $char === '+' || $char === '?') {
                $pos++;
                continue; // 简化: 不完整处理量词
            }
            $next = $nfa->newState();
            $nfa->addChar($current, $char, $next);
            $current = $next;
            $pos++;
        }
        return $current;
    }
}

class BacktrackingRegex {
    private string $pattern;
    private array $captures = [];

    public function __construct(string $pattern) { $this->pattern = $pattern; }

    public function match(string $input): array {
        $this->captures = [];
        for ($start = 0; $start <= strlen($input); $start++) {
            $this->captures = [];
            $result = $this->matchHere($this->pattern, 0, $input, $start);
            if ($result !== false) {
                return ['match' => true, 'start' => $start, 'end' => $result, 'captures' => $this->captures];
            }
        }
        return ['match' => false];
    }

    private function matchHere(string $pattern, int $pi, string $input, int $ii): int|false {
        if ($pi >= strlen($pattern)) return $ii;
        // 量词 *
        if ($pi + 1 < strlen($pattern) && $pattern[$pi + 1] === '*') {
            return $this->matchStar($pattern[$pi], $pattern, $pi + 2, $input, $ii);
        }
        // 量词 +
        if ($pi + 1 < strlen($pattern) && $pattern[$pi + 1] === '+') {
            if ($ii < strlen($input) && $this->matchChar($pattern[$pi], $input[$ii])) {
                $r = $this->matchStar($pattern[$pi], $pattern, $pi + 2, $input, $ii + 1);
                if ($r !== false) return $r;
            }
            return false;
        }
        // 量词 ?
        if ($pi + 1 < strlen($pattern) && $pattern[$pi + 1] === '?') {
            $r = $this->matchHere($pattern, $pi + 2, $input, $ii);
            if ($r !== false) return $r;
            if ($ii < strlen($input) && $this->matchChar($pattern[$pi], $input[$ii])) {
                return $this->matchHere($pattern, $pi + 2, $input, $ii + 1);
            }
            return false;
        }
        // 通配符 .
        if ($pattern[$pi] === '.') {
            if ($ii >= strlen($input)) return false;
            return $this->matchHere($pattern, $pi + 1, $input, $ii + 1);
        }
        // 字符类 [a-z]
        if ($pattern[$pi] === '[') {
            $closePos = strpos($pattern, ']', $pi);
            if ($closePos !== false && $ii < strlen($input)) {
                $charClass = substr($pattern, $pi + 1, $closePos - $pi - 1);
                if ($this->matchCharClass($charClass, $input[$ii])) {
                    return $this->matchHere($pattern, $closePos + 1, $input, $ii + 1);
                }
            }
            return false;
        }
        // 锚 ^
        if ($pattern[$pi] === '^') return $this->matchHere($pattern, $pi + 1, $input, $ii);
        // 锚 $
        if ($pattern[$pi] === '$') return $ii === strlen($input) ? $ii : false;
        // 字面匹配
        if ($ii < strlen($input) && $this->matchChar($pattern[$pi], $input[$ii])) {
            return $this->matchHere($pattern, $pi + 1, $input, $ii + 1);
        }
        return false;
    }

    private function matchStar(string $c, string $pattern, int $pi, string $input, int $ii): int|false {
        // 贪婪匹配
        $maxMatch = $ii;
        while ($ii < strlen($input) && $this->matchChar($c, $input[$ii])) {
            $ii++;
            $maxMatch = $ii;
        }
        // 回溯
        while ($maxMatch >= 0) {
            $r = $this->matchHere($pattern, $pi, $input, $maxMatch);
            if ($r !== false) return $r;
            if ($maxMatch === 0) break;
            $maxMatch--;
        }
        return false;
    }

    private function matchChar(string $p, string $c): bool {
        if ($p === '.') return true;
        return $p === $c;
    }

    private function matchCharClass(string $class, string $c): bool {
        if (str_starts_with($class, '^')) {
            $class = substr($class, 1);
            $pos = 0;
            while ($pos < strlen($class)) {
                if ($pos + 2 < strlen($class) && $class[$pos + 1] === '-') {
                    if ($c >= $class[$pos] && $c <= $class[$pos + 2]) return false;
                    $pos += 3;
                } else {
                    if ($c === $class[$pos]) return false;
                    $pos++;
                }
            }
            return true;
        }
        $pos = 0;
        while ($pos < strlen($class)) {
            if ($pos + 2 < strlen($class) && $class[$pos + 1] === '-') {
                if ($c >= $class[$pos] && $c <= $class[$pos + 2]) return true;
                $pos += 3;
            } else {
                if ($c === $class[$pos]) return true;
                $pos++;
            }
        }
        return false;
    }

    public function findAll(string $input): array {
        $matches = [];
        $pos = 0;
        while ($pos <= strlen($input)) {
            $result = $this->match(substr($input, $pos));
            if ($result['match']) {
                $matches[] = ['match' => substr($input, $pos + $result['start'], $result['end'] - $result['start']), 'start' => $pos + $result['start'], 'end' => $pos + $result['end']];
                $pos += $result['end'] + 1;
            } else {
                $pos++;
            }
        }
        return $matches;
    }
}

// 测试
echo "--- Backtracking Regex ---\n";
$tests = [
    ['abc', 'abc', true],
    ['abc', 'abd', false],
    ['a.c', 'abc', true],
    ['a.c', 'axc', true],
    ['a.c', 'ac', false],
    ['a*b', 'aaab', true],
    ['a*b', 'b', true],
    ['a+b', 'aaab', true],
    ['a+b', 'b', false],
    ['a?b', 'ab', true],
    ['a?b', 'b', true],
    ['[abc]', 'a', true],
    ['[abc]', 'd', false],
    ['[a-z]', 'm', true],
    ['[a-z]', '5', false],
    ['[^abc]', 'd', true],
    ['[^abc]', 'a', false],
    ['^abc', 'abc', true],
    ['^abc', 'xabc', false],
    ['abc$', 'abc', true],
    ['abc$', 'abcd', false],
];
foreach ($tests as [$pattern, $input, $expected]) {
    $regex = new BacktrackingRegex($pattern);
    $result = $regex->match($input);
    $status = $result['match'] === $expected ? '✓' : '✗';
    echo "  $status /$pattern/ ~ \"$input\" → " . var_export($result['match'], true) . " (expected " . var_export($expected, true) . ")\n";
}

echo "\n--- Find All ---\n";
$regex = new BacktrackingRegex('a*b');
$matches = $regex->findAll('aaab aab b aaab');
echo "Pattern: /a*b/ in 'aaab aab b aaab'\n";
foreach ($matches as $m) echo "  Match: \"{$m['match']}\" at [{$m['start']}, {$m['end']}]\n";

echo "\n--- Capture Groups (simplified) ---\n";
$regex2 = new BacktrackingRegex('([a-z]+)([0-9]+)');
$result = $regex2->match('abc123');
echo "Pattern: /([a-z]+)([0-9]+)/ ~ 'abc123'\n";
echo "Match: " . var_export($result['match'], true) . "\n";
echo "Captures: " . json_encode($result['captures']) . "\n";

echo "\n--- Pattern Validation ---\n";
$patterns = [
    'email' => '[a-z]+@[a-z]+\\.[a-z]+',
    'phone' => '[0-9]{3}-[0-9]{4}',
    'date' => '[0-9]{4}/[0-9]{2}/[0-9]{2}',
    'ip' => '[0-9]+\\.[0-9]+\\.[0-9]+\\.[0-9]+',
];
$testInputs = [
    'email' => ['alice@test.com', 'bob@example.org', 'invalid', 'test@test'],
    'phone' => ['123-4567', '555-0000', '12-34', 'abc-defg'],
    'date' => ['2024/01/15', '2024/12/31', '24/1/1', 'invalid'],
    'ip' => ['192.168.1.1', '10.0.0.1', '999.999.999.999', 'not-an-ip'],
];
foreach ($patterns as $type => $pattern) {
    echo "  $type: pattern=/$pattern/\n";
    foreach ($testInputs[$type] as $input) {
        $regex = new BacktrackingRegex($pattern);
        $result = $regex->match($input);
        echo "    \"$input\" → " . var_export($result['match'], true) . "\n";
    }
}

echo "=== f129 Done ===\n";
