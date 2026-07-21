<?php
// 极度混搭: 字符串算法 + 后缀数组 + 最长公共子串 + 编辑距离 + 模式匹配
echo "=== f139: String Algo + SuffixArray + LCS + EditDistance ===\n";

class StringAlgorithms {
    public static function editDistance(string $s1, string $s2): array {
        $m = strlen($s1); $n = strlen($s2);
        $dp = [];
        for ($i = 0; $i <= $m; $i++) { $dp[$i] = []; $dp[$i][0] = $i; }
        for ($j = 0; $j <= $n; $j++) $dp[0][$j] = $j;
        for ($i = 1; $i <= $m; $i++) {
            for ($j = 1; $j <= $n; $j++) {
                if ($s1[$i - 1] === $s2[$j - 1]) $dp[$i][$j] = $dp[$i - 1][$j - 1];
                else $dp[$i][$j] = 1 + min($dp[$i - 1][$j], $dp[$i][$j - 1], $dp[$i - 1][$j - 1]);
            }
        }
        // 回溯
        $ops = [];
        $i = $m; $j = $n;
        while ($i > 0 || $j > 0) {
            if ($i > 0 && $j > 0 && $s1[$i - 1] === $s2[$j - 1]) { $i--; $j--; }
            elseif ($i > 0 && $j > 0 && $dp[$i][$j] === $dp[$i - 1][$j - 1] + 1) { $ops[] = "replace '{$s1[$i-1]}' → '{$s2[$j-1]}'"; $i--; $j--; }
            elseif ($i > 0 && $dp[$i][$j] === $dp[$i - 1][$j] + 1) { $ops[] = "delete '{$s1[$i-1]}'"; $i--; }
            else { $ops[] = "insert '{$s2[$j-1]}'"; $j--; }
        }
        return ['distance' => $dp[$m][$n], 'operations' => array_reverse($ops)];
    }

    public static function longestCommonSubsequence(string $s1, string $s2): string {
        $m = strlen($s1); $n = strlen($s2);
        $dp = array_fill(0, $m + 1, array_fill(0, $n + 1, 0));
        for ($i = 1; $i <= $m; $i++) {
            for ($j = 1; $j <= $n; $j++) {
                if ($s1[$i - 1] === $s2[$j - 1]) $dp[$i][$j] = $dp[$i - 1][$j - 1] + 1;
                else $dp[$i][$j] = max($dp[$i - 1][$j], $dp[$i][$j - 1]);
            }
        }
        $result = '';
        $i = $m; $j = $n;
        while ($i > 0 && $j > 0) {
            if ($s1[$i - 1] === $s2[$j - 1]) { $result = $s1[$i - 1] . $result; $i--; $j--; }
            elseif ($dp[$i - 1][$j] > $dp[$i][$j - 1]) $i--;
            else $j--;
        }
        return $result;
    }

    public static function longestCommonSubstring(string $s1, string $s2): string {
        $m = strlen($s1); $n = strlen($s2);
        $dp = array_fill(0, $m + 1, array_fill(0, $n + 1, 0));
        $maxLen = 0; $endPos = 0;
        for ($i = 1; $i <= $m; $i++) {
            for ($j = 1; $j <= $n; $j++) {
                if ($s1[$i - 1] === $s2[$j - 1]) {
                    $dp[$i][$j] = $dp[$i - 1][$j - 1] + 1;
                    if ($dp[$i][$j] > $maxLen) { $maxLen = $dp[$i][$j]; $endPos = $i; }
                }
            }
        }
        return substr($s1, $endPos - $maxLen, $maxLen);
    }

    public static function kmpSearch(string $text, string $pattern): array {
        $n = strlen($text); $m = strlen($pattern);
        if ($m === 0) return [];
        $lps = self::computeLPS($pattern);
        $matches = [];
        $i = 0; $j = 0;
        while ($i < $n) {
            if ($pattern[$j] === $text[$i]) { $i++; $j++; }
            if ($j === $m) { $matches[] = $i - $j; $j = $lps[$j - 1]; }
            elseif ($i < $n && $pattern[$j] !== $text[$i]) {
                if ($j !== 0) $j = $lps[$j - 1];
                else $i++;
            }
        }
        return $matches;
    }

    private static function computeLPS(string $pattern): array {
        $m = strlen($pattern);
        $lps = array_fill(0, $m, 0);
        $len = 0; $i = 1;
        while ($i < $m) {
            if ($pattern[$i] === $pattern[$len]) { $len++; $lps[$i] = $len; $i++; }
            else {
                if ($len !== 0) $len = $lps[$len - 1];
                else { $lps[$i] = 0; $i++; }
            }
        }
        return $lps;
    }

    public static function buildSuffixArray(string $s): array {
        $n = strlen($s);
        $suffixes = [];
        for ($i = 0; $i < $n; $i++) $suffixes[] = ['idx' => $i, 'suffix' => substr($s, $i)];
        usort($suffixes, fn($a, $b) => strcmp($a['suffix'], $b['suffix']));
        return array_map(fn($s) => $s['idx'], $suffixes);
    }

    public static function zAlgorithm(string $s): array {
        $n = strlen($s);
        $z = array_fill(0, $n, 0);
        $l = 0; $r = 0;
        for ($i = 1; $i < $n; $i++) {
            if ($i < $r) $z[$i] = min($r - $i, $z[$i - $l]);
            while ($i + $z[$i] < $n && $s[$z[$i]] === $s[$i + $z[$i]]) $z[$i]++;
            if ($i + $z[$i] > $r) { $l = $i; $r = $i + $z[$i]; }
        }
        return $z;
    }

    public static function manacher(string $s): array {
        $t = '^#' . implode('#', str_split($s)) . '#$';
        $n = strlen($t);
        $p = array_fill(0, $n, 0);
        $c = 0; $r = 0;
        for ($i = 1; $i < $n - 1; $i++) {
            $mirror = 2 * $c - $i;
            if ($i < $r) $p[$i] = min($r - $i, $p[$mirror]);
            while ($t[$i + $p[$i] + 1] === $t[$i - $p[$i] - 1]) $p[$i]++;
            if ($i + $p[$i] > $r) { $c = $i; $r = $i + $p[$i]; }
        }
        $maxLen = max($p);
        $center = array_search($maxLen, $p);
        $start = (int)(($center - $maxLen) / 2);
        return ['longest' => substr($s, $start, $maxLen), 'length' => $maxLen, 'start' => $start];
    }

    public static function rabinKarp(string $text, string $pattern): array {
        $n = strlen($text); $m = strlen($pattern);
        if ($m === 0 || $m > $n) return [];
        $base = 256; $mod = 1000000007;
        $patternHash = 0; $textHash = 0; $h = 1;
        for ($i = 0; $i < $m - 1; $i++) $h = ($h * $base) % $mod;
        for ($i = 0; $i < $m; $i++) {
            $patternHash = ($patternHash * $base + ord($pattern[$i])) % $mod;
            $textHash = ($textHash * $base + ord($text[$i])) % $mod;
        }
        $matches = [];
        for ($i = 0; $i <= $n - $m; $i++) {
            if ($patternHash === $textHash) {
                $match = true;
                for ($j = 0; $j < $m; $j++) {
                    if ($text[$i + $j] !== $pattern[$j]) { $match = false; break; }
                }
                if ($match) $matches[] = $i;
            }
            if ($i < $n - $m) {
                $textHash = ($base * ($textHash - ord($text[$i]) * $h) + ord($text[$i + $m])) % $mod;
                if ($textHash < 0) $textHash += $mod;
            }
        }
        return $matches;
    }
}

// 测试
echo "--- Edit Distance ---\n";
$ed = StringAlgorithms::editDistance('kitten', 'sitting');
echo "'kitten' → 'sitting': distance={$ed['distance']}\n";
echo "Operations:\n";
foreach ($ed['operations'] as $op) echo "  $op\n";

$ed2 = StringAlgorithms::editDistance('sunday', 'saturday');
echo "\n'sunday' → 'saturday': distance={$ed2['distance']}\n";

echo "\n--- Longest Common Subsequence ---\n";
$lcs = StringAlgorithms::longestCommonSubsequence('ABCBDAB', 'BDCABA');
echo "LCS('ABCBDAB', 'BDCABA') = '$lcs' (length=" . strlen($lcs) . ")\n";

echo "\n--- Longest Common Substring ---\n";
$lcsub = StringAlgorithms::longestCommonSubstring('ABABC', 'BABCA');
echo "LCSubstr('ABABC', 'BABCA') = '$lcsub'\n";

echo "\n--- KMP Pattern Matching ---\n";
$matches = StringAlgorithms::kmpSearch('ABABDABACDABABCABAB', 'ABABCABAB');
echo "Pattern 'ABABCABAB' found at positions: " . implode(', ', $matches) . "\n";
$matches2 = StringAlgorithms::kmpSearch('aaaaaa', 'aa');
echo "Pattern 'aa' in 'aaaaaa': " . implode(', ', $matches2) . "\n";

echo "\n--- Suffix Array ---\n";
$sa = StringAlgorithms::buildSuffixArray('banana');
echo "Suffix array of 'banana': [" . implode(', ', $sa) . "]\n";
foreach ($sa as $idx) echo "  $idx: " . substr('banana', $idx) . "\n";

echo "\n--- Z Algorithm ---\n";
$z = StringAlgorithms::zAlgorithm('aabcaabxaaaz');
echo "Z array: [" . implode(', ', $z) . "]\n";

echo "\n--- Manacher's Algorithm (Longest Palindrome) ---\n";
$palindromes = ['babad', 'cbbd', 'racecar', 'a', 'ab'];
foreach ($palindromes as $s) {
    $result = StringAlgorithms::manacher($s);
    echo "  '$s' → longest='{$result['longest']}' (len={$result['length']})\n";
}

echo "\n--- Rabin-Karp ---\n";
$rkMatches = StringAlgorithms::rabinKarp('GEEKS FOR GEEKS', 'GEEKS');
echo "Rabin-Karp: 'GEEKS' in 'GEEKS FOR GEEKS' at: " . implode(', ', $rkMatches) . "\n";

echo "\n--- String Distance Comparison ---\n";
$pairs = [
    ['hello', 'hallo'], ['world', 'word'], ['algorithm', 'rhythm'],
    ['computer', 'commuter'], ['php', 'python'],
];
foreach ($pairs as [$a, $b]) {
    $ed = StringAlgorithms::editDistance($a, $b);
    echo "  '$a' ↔ '$b': distance={$ed['distance']}\n";
}

echo "\n--- Multiple Pattern Search ---\n";
$text = 'the quick brown fox jumps over the lazy dog the fox';
$patterns = ['the', 'fox', 'dog', 'cat'];
foreach ($patterns as $p) {
    $kmp = StringAlgorithms::kmpSearch($text, $p);
    $rk = StringAlgorithms::rabinKarp($text, $p);
    echo "  '$p': KMP=[" . implode(',', $kmp) . "] RK=[" . implode(',', $rk) . "] match=" . var_export($kmp === $rk, true) . "\n";
}

echo "=== f139 Done ===\n";
