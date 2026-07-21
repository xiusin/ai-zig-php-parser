<?php
// 极度混搭: NFA字符串搜索 + 模式匹配 + 状态转换 + Thompson构造
echo "=== f058: NFA + String Search + Pattern Match ===\n";

class NFANode {
    public array $transitions = []; // char → array of NFANode
    public array $epsilon = []; // epsilon transitions

    public function addTransition(string $char, NFANode $node): void {
        $this->transitions[$char][] = $node;
    }

    public function addEpsilon(NFANode $node): void {
        $this->epsilon[] = $node;
    }
}

class NFA {
    private NFANode $start;
    private NFANode $accept;

    public function __construct(NFANode $start, NFANode $accept) {
        $this->start = $start;
        $this->accept = $accept;
    }

    public static function fromChar(string $char): self {
        $start = new NFANode();
        $accept = new NFANode();
        $start->addTransition($char, $accept);
        return new self($start, $accept);
    }

    public static function concat(self $a, self $b): self {
        $a->accept->addEpsilon($b->start);
        return new self($a->start, $b->accept);
    }

    public static function alternation(self $a, self $b): self {
        $start = new NFANode();
        $accept = new NFANode();
        $start->addEpsilon($a->start);
        $start->addEpsilon($b->start);
        $a->accept->addEpsilon($accept);
        $b->accept->addEpsilon($accept);
        return new self($start, $accept);
    }

    public static function star(self $a): self {
        $start = new NFANode();
        $accept = new NFANode();
        $start->addEpsilon($a->start);
        $start->addEpsilon($accept);
        $a->accept->addEpsilon($a->start);
        $a->accept->addEpsilon($accept);
        return new self($start, $accept);
    }

    public static function plus(self $a): self {
        $start = new NFANode();
        $accept = new NFANode();
        $start->addEpsilon($a->start);
        $a->accept->addEpsilon($a->start);
        $a->accept->addEpsilon($accept);
        return new self($start, $accept);
    }

    public static function optional(self $a): self {
        $start = new NFANode();
        $accept = new NFANode();
        $start->addEpsilon($a->start);
        $start->addEpsilon($accept);
        $a->accept->addEpsilon($accept);
        return new self($start, $accept);
    }

    public function match(string $input): bool {
        $current = [$this->start];
        $current = $this->epsilonClosure($current);

        for ($i = 0; $i < strlen($input); $i++) {
            $char = $input[$i];
            $next = [];
            foreach ($current as $node) {
                if (isset($node->transitions[$char])) {
                    foreach ($node->transitions[$char] as $target) {
                        $next[] = $target;
                    }
                }
            }
            $current = $this->epsilonClosure($next);
            if (empty($current)) return false;
        }

        foreach ($current as $node) {
            if ($node === $this->accept) return true;
        }
        return false;
    }

    private function epsilonClosure(array $nodes): array {
        $closure = [];
        $stack = $nodes;
        while (!empty($stack)) {
            $node = array_pop($stack);
            $id = spl_object_id($node);
            if (isset($closure[$id])) continue;
            $closure[$id] = $node;
            foreach ($node->epsilon as $eps) {
                $stack[] = $eps;
            }
        }
        return array_values($closure);
    }
}

// 简化的字符串搜索（不使用NFA，使用多种算法）
class StringSearch {
    public static function naive(string $text, string $pattern): array {
        $positions = [];
        $n = strlen($text);
        $m = strlen($pattern);
        if ($m === 0 || $m > $n) return $positions;
        for ($i = 0; $i <= $n - $m; $i++) {
            $match = true;
            for ($j = 0; $j < $m; $j++) {
                if ($text[$i + $j] !== $pattern[$j]) { $match = false; break; }
            }
            if ($match) $positions[] = $i;
        }
        return $positions;
    }

    public static function kmp(string $text, string $pattern): array {
        $positions = [];
        $n = strlen($text);
        $m = strlen($pattern);
        if ($m === 0 || $m > $n) return $positions;

        // Build failure function
        $fail = array_fill(0, $m, 0);
        $k = 0;
        for ($i = 1; $i < $m; $i++) {
            while ($k > 0 && $pattern[$k] !== $pattern[$i]) $k = $fail[$k - 1];
            if ($pattern[$k] === $pattern[$i]) $k++;
            $fail[$i] = $k;
        }

        // Search
        $k = 0;
        for ($i = 0; $i < $n; $i++) {
            while ($k > 0 && $pattern[$k] !== $text[$i]) $k = $fail[$k - 1];
            if ($pattern[$k] === $text[$i]) $k++;
            if ($k === $m) {
                $positions[] = $i - $m + 1;
                $k = $fail[$k - 1];
            }
        }
        return $positions;
    }

    public static function rabinKarp(string $text, string $pattern): array {
        $positions = [];
        $n = strlen($text);
        $m = strlen($pattern);
        if ($m === 0 || $m > $n) return $positions;

        $base = 256;
        $mod = 1000000007;
        $patternHash = 0;
        $textHash = 0;
        $h = 1;

        for ($i = 0; $i < $m - 1; $i++) $h = ($h * $base) % $mod;
        for ($i = 0; $i < $m; $i++) {
            $patternHash = ($patternHash * $base + ord($pattern[$i])) % $mod;
            $textHash = ($textHash * $base + ord($text[$i])) % $mod;
        }

        for ($i = 0; $i <= $n - $m; $i++) {
            if ($patternHash === $textHash) {
                $match = true;
                for ($j = 0; $j < $m; $j++) {
                    if ($text[$i + $j] !== $pattern[$j]) { $match = false; break; }
                }
                if ($match) $positions[] = $i;
            }
            if ($i < $n - $m) {
                $textHash = (($textHash - ord($text[$i]) * $h) * $base + ord($text[$i + $m])) % $mod;
                if ($textHash < 0) $textHash += $mod;
            }
        }
        return $positions;
    }
}

// 测试
echo "--- NFA Matching ---\n";
// 'ab' 串联
$ab = NFA::concat(NFA::fromChar('a'), NFA::fromChar('b'));
echo "match 'ab' on 'ab': " . var_export($ab->match('ab'), true) . "\n";
echo "match 'ab' on 'abc': " . var_export($ab->match('abc'), true) . "\n";
echo "match 'ab' on 'ac': " . var_export($ab->match('ac'), true) . "\n";

// 'a|b' 选择
$ab2 = NFA::alternation(NFA::fromChar('a'), NFA::fromChar('b'));
echo "match 'a|b' on 'a': " . var_export($ab2->match('a'), true) . "\n";
echo "match 'a|b' on 'b': " . var_export($ab2->match('b'), true) . "\n";
echo "match 'a|b' on 'c': " . var_export($ab2->match('c'), true) . "\n";

// 'a*' 星号
$star = NFA::star(NFA::fromChar('a'));
echo "match 'a*' on '': " . var_export($star->match(''), true) . "\n";
echo "match 'a*' on 'a': " . var_export($star->match('a'), true) . "\n";
echo "match 'a*' on 'aaa': " . var_export($star->match('aaa'), true) . "\n";
echo "match 'a*' on 'b': " . var_export($star->match('b'), true) . "\n";

// 'a+' 加号
$plus = NFA::plus(NFA::fromChar('a'));
echo "match 'a+' on '': " . var_export($plus->match(''), true) . "\n";
echo "match 'a+' on 'a': " . var_export($plus->match('a'), true) . "\n";
echo "match 'a+' on 'aaa': " . var_export($plus->match('aaa'), true) . "\n";

echo "\n--- String Search ---\n";
$text = "ABABDABACDABABCABAB";
$pattern = "ABABCABAB";
echo "Text: $text\n";
echo "Pattern: $pattern\n";
echo "Naive: " . json_encode(StringSearch::naive($text, $pattern)) . "\n";
echo "KMP: " . json_encode(StringSearch::kmp($text, $pattern)) . "\n";
echo "RabinKarp: " . json_encode(StringSearch::rabinKarp($text, $pattern)) . "\n";

$text2 = "AAAAAAAABAAAA";
$pattern2 = "AAAA";
echo "\nText: $text2\n";
echo "Pattern: $pattern2\n";
echo "Naive: " . json_encode(StringSearch::naive($text2, $pattern2)) . "\n";
echo "KMP: " . json_encode(StringSearch::kmp($text2, $pattern2)) . "\n";
echo "RabinKarp: " . json_encode(StringSearch::rabinKarp($text2, $pattern2)) . "\n";

$text3 = "hello world hello php hello";
$pattern3 = "hello";
echo "\nText: $text3\n";
echo "Pattern: $pattern3\n";
echo "KMP: " . json_encode(StringSearch::kmp($text3, $pattern3)) . "\n";

echo "=== f058 Done ===\n";
