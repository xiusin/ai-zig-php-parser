<?php
function isPalindrome(string $str): bool {
    $str = strtolower(preg_replace('/[^a-z0-9]/', '', $str));
    return $str === strrev($str);
}

function isAnagram(string $a, string $b): bool {
    $a = strtolower(preg_replace('/[^a-z]/', '', $a));
    $b = strtolower(preg_replace('/[^a-z]/', '', $b));

    if (strlen($a) !== strlen($b)) return false;

    $counts = [];
    for ($i = 0; $i < strlen($a); $i++) {
        $counts[$a[$i]] = ($counts[$a[$i]] ?? 0) + 1;
        $counts[$b[$i]] = ($counts[$b[$i]] ?? 0) - 1;
    }

    foreach ($counts as $count) {
        if ($count !== 0) return false;
    }
    return true;
}

function longestCommonPrefix(array $strs): string {
    if (empty($strs)) return '';

    $prefix = $strs[0];
    for ($i = 1; $i < count($strs); $i++) {
        while (strpos($strs[$i], $prefix) !== 0) {
            $prefix = substr($prefix, 0, -1);
            if ($prefix === '') return '';
        }
    }

    return $prefix;
}

function reverseString(string $str): string {
    return strrev($str);
}

echo isPalindrome("A man, a plan, a canal: Panama") ? 'true' : 'false' . "\n";
echo isPalindrome("Hello") ? 'true' : 'false' . "\n";
echo isAnagram("Listen", "Silent") ? 'true' : 'false' . "\n";
echo isAnagram("Hello", "World") ? 'true' : 'false' . "\n";
echo longestCommonPrefix(["flower", "flow", "flight"]) . "\n";
echo longestCommonPrefix(["dog", "racecar", "car"]) . "\n";
echo "OK\n";
