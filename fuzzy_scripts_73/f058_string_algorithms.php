<?php
// f058: 字符串算法集合
// 测试 substr 在复杂上下文中的行为

echo "=== String Algorithms ===\n\n";

// 1. 字符串反转
function reverseString(string $s): string {
    $len = strlen($s);
    $result = '';
    for ($i = $len - 1; $i >= 0; $i--) {
        $result .= $s[$i];
    }
    return $result;
}

// 2. 检查回文
function isPalindrome(string $s): bool {
    $s = strtolower(preg_replace('/[^a-zA-Z0-9]/', '', $s));
    return $s === reverseString($s);
}

// 3. 字符串排列（递归）
function permutations(string $str): array {
    $result = [];
    if (strlen($str) <= 1) {
        $result[] = $str;
        return $result;
    }
    for ($i = 0; $i < strlen($str); $i++) {
        $char = $str[$i];
        $rest = substr($str, 0, $i) . substr($str, $i + 1);
        foreach (permutations($rest) as $perm) {
            $result[] = $char . $perm;
        }
    }
    return $result;
}

// 4. 最长公共前缀
function longestCommonPrefix(array $strs): string {
    if (empty($strs)) return '';
    $prefix = $strs[0];
    for ($i = 1; $i < count($strs); $i++) {
        while (strlen($prefix) > 0 && strpos($strs[$i], substr($prefix, 0, strlen($prefix))) !== 0) {
            $prefix = substr($prefix, 0, -1);
        }
        if (strlen($prefix) === 0) return '';
    }
    return $prefix;
}

// 5. 字符串压缩（游程编码）
function runLengthEncode(string $s): string {
    if (empty($s)) return '';
    $result = '';
    $count = 1;
    $prev = $s[0];
    for ($i = 1; $i < strlen($s); $i++) {
        if ($s[$i] === $prev) {
            $count++;
        } else {
            $result .= $prev . $count;
            $prev = $s[$i];
            $count = 1;
        }
    }
    $result .= $prev . $count;
    return $result;
}

// 6. 查找所有子串
function allSubstrings(string $s): array {
    $result = [];
    $len = strlen($s);
    for ($i = 0; $i < $len; $i++) {
        for ($j = $i + 1; $j <= $len; $j++) {
            $result[] = substr($s, $i, $j - $i);
        }
    }
    return $result;
}

// 7. 字符串匹配（KMP）
function kmpSearch(string $text, string $pattern): int {
    $n = strlen($text);
    $m = strlen($pattern);
    if ($m === 0) return 0;
    if ($n < $m) return -1;

    // 构建失败函数
    $fail = [0];
    $j = 0;
    for ($i = 1; $i < $m; $i++) {
        while ($j > 0 && $pattern[$i] !== $pattern[$j]) {
            $j = $fail[$j - 1];
        }
        if ($pattern[$i] === $pattern[$j]) {
            $j++;
        }
        $fail[$i] = $j;
    }

    // 搜索
    $j = 0;
    for ($i = 0; $i < $n; $i++) {
        while ($j > 0 && $text[$i] !== $pattern[$j]) {
            $j = $fail[$j - 1];
        }
        if ($text[$i] === $pattern[$j]) {
            $j++;
        }
        if ($j === $m) {
            return $i - $m + 1;
        }
    }
    return -1;
}

// === 测试 ===

echo "--- Reverse String ---\n";
echo reverseString('hello') . "\n";
echo reverseString('world') . "\n";
echo reverseString('') . "\n";

echo "\n--- Palindrome Check ---\n";
echo isPalindrome('racecar') ? 'true' : 'false';
echo "\n";
echo isPalindrome('hello') ? 'true' : 'false';
echo "\n";
echo isPalindrome('A man a plan a canal Panama') ? 'true' : 'false';
echo "\n";

echo "\n--- Permutations ---\n";
$perms = permutations('abc');
echo implode(', ', $perms) . "\n";
$perms2 = permutations('ab');
echo implode(', ', $perms2) . "\n";

echo "\n--- Unique Permutations ---\n";
$perms3 = array_unique(permutations('aab'));
sort($perms3);
echo implode(', ', $perms3) . "\n";

echo "\n--- Longest Common Prefix ---\n";
$lcp1 = longestCommonPrefix(['flower', 'flow', 'flight']);
echo "['flower','flow','flight'] -> '$lcp1'\n";
$lcp2 = longestCommonPrefix(['dog', 'racecar', 'car']);
echo "['dog','racecar','car'] -> '$lcp2'\n";
$lcp3 = longestCommonPrefix(['interspecies', 'interstellar', 'interstate']);
echo "['interspecies','interstellar','interstate'] -> '$lcp3'\n";
$lcp4 = longestCommonPrefix(['prefix', 'pre']);
echo "['prefix','pre'] -> '$lcp4'\n";

echo "\n--- Run Length Encode ---\n";
echo runLengthEncode('aaabbc') . "\n";
echo runLengthEncode('abcdef') . "\n";
echo runLengthEncode('') . "\n";
echo runLengthEncode('aaaaaa') . "\n";

echo "\n--- All Substrings ---\n";
$subs = allSubstrings('abc');
echo implode(', ', $subs) . "\n";

echo "\n--- KMP Search ---\n";
echo kmpSearch('hello world', 'world') . "\n";
echo kmpSearch('aaaaaaab', 'aaab') . "\n";
echo kmpSearch('abcdef', 'xyz') . "\n";
echo kmpSearch('abcabc', 'abc') . "\n";
