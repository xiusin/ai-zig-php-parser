<?php
// 极度混搭: 正则引擎简化 + NFA构造 + 匹配 + 捕获组
echo "=== f094: Regex Engine + NFA + Capture Groups ===\n";

class RegexNFA {
    private array $states = [];
    private int $stateCount = 0;
    private int $start = 0;
    private array $accepts = [];
    private array $captures = [];

    private function newState(): int { return $this->stateCount++; }

    public function __construct(private string $pattern) {
        $this->start = $this->newState();
        $end = $this->parse(0, strlen($pattern), $this->start);
        $this->accepts[] = $end;
    }

    private function parse(int $start, int $end, int $entry): int {
        $current = $entry;
        $i = $start;
        $groupStart = $current;
        while ($i < $end) {
            $char = $this->pattern[$i];
            if ($char === '(') {
                $depth = 1; $j = $i + 1;
                while ($j < $end && $depth > 0) {
                    if ($this->pattern[$j] === '(') $depth++;
                    elseif ($this->pattern[$j] === ')') $depth--;
                    if ($depth > 0) $j++;
                }
                $inner = $this->parse($i + 1, $j, $this->newState());
                $this->addEpsilon($current, $inner);
                $current = $this->newState();
                $this->addEpsilon($inner, $current);
                $i = $j + 1;
            } elseif ($char === '*') {
                $loop = $this->newState();
                $this->addEpsilon($current, $loop);
                $this->addEpsilon($loop, $groupStart);
                $exit = $this->newState();
                $this->addEpsilon($current, $exit);
                $current = $exit;
                $i++;
            } elseif ($char === '+') {
                $exit = $this->newState();
                $this->addEpsilon($current, $groupStart);
                $this->addEpsilon($current, $exit);
                $current = $exit;
                $i++;
            } elseif ($char === '?') {
                $exit = $this->newState();
                $this->addEpsilon($current, $exit);
                $current = $exit;
                $i++;
            } elseif ($char === '.') {
                $next = $this->newState();
                $this->addAny($current, $next);
                $current = $next;
                $groupStart = $current;
                $i++;
            } else {
                $next = $this->newState();
                $this->addTransition($current, $char, $next);
                $current = $next;
                $groupStart = $current;
                $i++;
            }
        }
        return $current;
    }

    private function addTransition(int $from, string $char, int $to): void {
        $this->states[$from]['trans'][$char][] = $to;
    }
    private function addEpsilon(int $from, int $to): void {
        $this->states[$from]['eps'][] = $to;
    }
    private function addAny(int $from, int $to): void {
        $this->states[$from]['any'][] = $to;
    }

    public function match(string $input): bool {
        $current = $this->epsilonClosure([$this->start]);
        for ($i = 0; $i < strlen($input); $i++) {
            $char = $input[$i];
            $next = [];
            foreach ($current as $state) {
                if (isset($this->states[$state]['trans'][$char])) {
                    foreach ($this->states[$state]['trans'][$char] as $t) $next[] = $t;
                }
                if (isset($this->states[$state]['any'])) {
                    foreach ($this->states[$state]['any'] as $t) $next[] = $t;
                }
            }
            $current = $this->epsilonClosure($next);
            if (empty($current)) return false;
        }
        foreach ($current as $state) {
            if (in_array($state, $this->accepts)) return true;
        }
        return false;
    }

    private function epsilonClosure(array $states): array {
        $closure = []; $stack = $states;
        while (!empty($stack)) {
            $s = array_pop($stack);
            if (isset($closure[$s])) continue;
            $closure[$s] = true;
            if (isset($this->states[$s]['eps'])) {
                foreach ($this->states[$s]['eps'] as $e) $stack[] = $e;
            }
        }
        return array_keys($closure);
    }
}

class SimpleRegex {
    public static function match(string $pattern, string $input): bool {
        $nfa = new RegexNFA($pattern);
        return $nfa->match($input);
    }

    public static function matchUsingPHP(string $pattern, string $input): int {
        return preg_match('/' . str_replace('/', '\/', $pattern) . '/', $input);
    }

    public static function extractGroups(string $pattern, string $input): array {
        $results = [];
        if (preg_match_all('/' . str_replace('/', '\/', $pattern) . '/', $input, $matches)) {
            for ($i = 1; $i < count($matches); $i++) {
                if (!empty($matches[$i])) $results[] = $matches[$i][0];
            }
        }
        return $results;
    }

    public static function validate(string $pattern, string $input): bool {
        return preg_match('/^' . str_replace('/', '\/', $pattern) . '$/', $input) === 1;
    }

    public static function replace(string $pattern, string $replacement, string $input): string {
        return preg_replace('/' . str_replace('/', '\/', $pattern) . '/', $replacement, $input);
    }
}

// 测试
echo "--- Simple Pattern Matching ---\n";
$patterns = ['abc', 'a.c', 'ab*c', 'ab+c', 'ab?c'];
$inputs = ['abc', 'ac', 'abbbc', 'abbc', 'axc', 'a'];

foreach ($patterns as $pat) {
    echo "\nPattern: $pat\n";
    foreach ($inputs as $in) {
        $my = SimpleRegex::match($pat, $in);
        echo "  '$in' → " . var_export($my, true) . "\n";
    }
}

echo "\n--- PHP Regex Matching ---\n";
$regexTests = [
    ['\d+', 'hello 123 world', true],
    ['\d+', 'no numbers here', false],
    ['[a-z]+', 'abc', true],
    ['[A-Z]+', 'ABC', true],
    ['\w+@\w+', 'user@domain', true],
    ['^abc$', 'abc', true],
    ['^abc$', 'abcd', false],
];
foreach ($regexTests as [$pat, $input, $expected]) {
    $result = SimpleRegex::validate($pat, $input);
    echo "  validate('$pat', '$input') = " . var_export($result, true) . " (expected " . var_export($expected, true) . ")\n";
}

echo "\n--- Capture Groups ---\n";
$groupTests = [
    ['(\d+)-(\d+)', 'phone 123-456'],
    ['(\w+)@(\w+)', 'email user@example'],
    ['(\d{4})-(\d{2})-(\d{2})', 'date 2024-01-15'],
];
foreach ($groupTests as [$pat, $input]) {
    $groups = SimpleRegex::extractGroups($pat, $input);
    echo "  '$pat' on '$input' → groups: " . json_encode($groups) . "\n";
}

echo "\n--- Replace ---\n";
$replaces = [
    ['\d+', '#', 'hello 123 world 456'],
    ['[aeiou]', '*', 'hello world'],
    ['\s+', '_', 'hello  world   php'],
];
foreach ($replaces as [$pat, $rep, $input]) {
    $result = SimpleRegex::replace($pat, $rep, $input);
    echo "  replace('$pat', '$rep') → '$result'\n";
}

echo "\n--- Email Validation ---\n";
$emails = ['user@example.com', 'invalid', '@nope.com', 'a@b.c', 'test.email+tag@domain.co.uk'];
foreach ($emails as $email) {
    $valid = SimpleRegex::validate('[\w.+-]+@[\w.-]+\.[a-z]{2,}', $email);
    echo "  '$email' → " . var_export($valid, true) . "\n";
}

echo "=== f094 Done ===\n";
