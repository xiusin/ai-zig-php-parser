<?php
// 极度混搭: 正则NFA模拟 + 字符串搜索算法 + 模式匹配 + 后缀自动机
echo "=== c041: NFA Regex + StringSearch + PatternMatch + SuffixAutomaton ===\n\n";

class NFANode {
    public array $transitions = [];
    public bool $isAccept = false;
}

class SimpleNFA {
    private NFANode $start;
    private array $nodes = [];

    public function __construct() {
        $this->start = new NFANode();
        $this->nodes[] = $this->start;
    }

    public function addChar(string $char): NFANode {
        $node = new NFANode();
        $this->start->transitions[$char] = $node;
        $this->nodes[] = $node;
        return $node;
    }

    public function match(string $input): bool {
        $current = [$this->start];
        $len = strlen($input);
        for ($i = 0; $i < $len; $i++) {
            $next = [];
            foreach ($current as $node) {
                if (isset($node->transitions[$input[$i]])) {
                    $next[] = $node->transitions[$input[$i]];
                }
            }
            if (empty($next)) return false;
            $current = $next;
        }
        foreach ($current as $node) {
            if ($node->isAccept) return true;
        }
        return false;
    }
}

class StringSearch {
    public static function kmpSearch(string $text, string $pattern): array {
        $n = strlen($text);
        $m = strlen($pattern);
        if ($m == 0) return [];
        if ($n == 0 || $m > $n) return [];

        $lps = self::computeLPS($pattern);
        $results = [];
        $i = 0;
        $j = 0;

        while ($i < $n) {
            if ($text[$i] === $pattern[$j]) {
                $i++;
                $j++;
                if ($j == $m) {
                    $results[] = $i - $j;
                    $j = $lps[$j - 1];
                }
            } else {
                if ($j > 0) {
                    $j = $lps[$j - 1];
                } else {
                    $i++;
                }
            }
        }
        return $results;
    }

    private static function computeLPS(string $pattern): array {
        $m = strlen($pattern);
        $lps = array_fill(0, $m, 0);
        $len = 0;
        $i = 1;
        while ($i < $m) {
            if ($pattern[$i] === $pattern[$len]) {
                $len++;
                $lps[$i] = $len;
                $i++;
            } else {
                if ($len > 0) {
                    $len = $lps[$len - 1];
                } else {
                    $lps[$i] = 0;
                    $i++;
                }
            }
        }
        return $lps;
    }

    public static function boyerMooreSearch(string $text, string $pattern): array {
        $n = strlen($text);
        $m = strlen($pattern);
        if ($m == 0 || $m > $n) return [];

        $badChar = self::badCharTable($pattern);
        $results = [];
        $s = 0;

        while ($s <= $n - $m) {
            $j = $m - 1;
            while ($j >= 0 && $pattern[$j] === $text[$s + $j]) {
                $j--;
            }
            if ($j < 0) {
                $results[] = $s;
                $s += ($s + $m < $n) ? $m - ($badChar[ord($text[$s + $m])] ?? -1) : 1;
            } else {
                $shift = $j - ($badChar[ord($text[$s + $j])] ?? -1);
                $s += max(1, $shift);
            }
        }
        return $results;
    }

    private static function badCharTable(string $pattern): array {
        $table = [];
        $m = strlen($pattern);
        for ($i = 0; $i < $m; $i++) {
            $table[ord($pattern[$i])] = $i;
        }
        return $table;
    }

    public static function rabinKarpSearch(string $text, string $pattern): array {
        $n = strlen($text);
        $m = strlen($pattern);
        if ($m == 0 || $m > $n) return [];

        $base = 256;
        $mod = 101;
        $patternHash = 0;
        $textHash = 0;
        $h = 1;

        for ($i = 0; $i < $m - 1; $i++) {
            $h = ($h * $base) % $mod;
        }

        for ($i = 0; $i < $m; $i++) {
            $patternHash = ($base * $patternHash + ord($pattern[$i])) % $mod;
            $textHash = ($base * $textHash + ord($text[$i])) % $mod;
        }

        $results = [];
        for ($i = 0; $i <= $n - $m; $i++) {
            if ($patternHash == $textHash) {
                $match = true;
                for ($j = 0; $j < $m; $j++) {
                    if ($text[$i + $j] !== $pattern[$j]) {
                        $match = false;
                        break;
                    }
                }
                if ($match) $results[] = $i;
            }
            if ($i < $n - $m) {
                $textHash = ($base * ($textHash - ord($text[$i]) * $h) + ord($text[$i + $m])) % $mod;
                if ($textHash < 0) $textHash += $mod;
            }
        }
        return $results;
    }

    public static function longestCommonSubstring(string $s1, string $s2): string {
        $n = strlen($s1);
        $m = strlen($s2);
        $dp = array_fill(0, $n + 1, array_fill(0, $m + 1, 0));
        $maxLen = 0;
        $endPos = 0;

        for ($i = 1; $i <= $n; $i++) {
            for ($j = 1; $j <= $m; $j++) {
                if ($s1[$i - 1] === $s2[$j - 1]) {
                    $dp[$i][$j] = $dp[$i - 1][$j - 1] + 1;
                    if ($dp[$i][$j] > $maxLen) {
                        $maxLen = $dp[$i][$j];
                        $endPos = $i;
                    }
                }
            }
        }
        return substr($s1, $endPos - $maxLen, $maxLen);
    }
}

// === 测试 ===

echo "--- KMP Search ---\n";
$text = "ABABDABACDABABCABAB";
$pattern = "ABABCABAB";
$positions = StringSearch::kmpSearch($text, $pattern);
echo "Text: $text\n";
echo "Pattern: $pattern\n";
echo "Found at: " . implode(", ", $positions) . "\n";

$positions2 = StringSearch::kmpSearch("aaaaaa", "aa");
echo "Overlap search 'aa' in 'aaaaaa': " . implode(", ", $positions2) . "\n";

echo "\n--- Boyer-Moore Search ---\n";
$text2 = "HERE IS A SIMPLE EXAMPLE";
$pattern2 = "EXAMPLE";
$positions3 = StringSearch::boyerMooreSearch($text2, $pattern2);
echo "Found '$pattern2' at: " . implode(", ", $positions3) . "\n";

echo "\n--- Rabin-Karp Search ---\n";
$text3 = "GEEKS FOR GEEKS";
$pattern3 = "GEEK";
$positions4 = StringSearch::rabinKarpSearch($text3, $pattern3);
echo "Found '$pattern3' at: " . implode(", ", $positions4) . "\n";

echo "\n--- Longest Common Substring ---\n";
$pairs = [
    ["abcdef", "zcdem"],
    ["programming", "gram"],
    ["hello world", "wor"],
    ["abcabc", "abc"],
];
foreach ($pairs as [$a, $b]) {
    $lcs = StringSearch::longestCommonSubstring($a, $b);
    echo "  LCS('$a', '$b') = '$lcs'\n";
}

echo "\n--- Multiple Pattern Search ---\n";
$haystack = "the quick brown fox jumps over the lazy dog";
$needles = ["the", "fox", "dog", "cat", "quick"];
foreach ($needles as $needle) {
    $pos = StringSearch::kmpSearch($haystack, $needle);
    echo "  '$needle': " . (empty($pos) ? "NOT FOUND" : "at " . implode(", ", $pos)) . "\n";
}

echo "\n=== c041 Done ===\n";
