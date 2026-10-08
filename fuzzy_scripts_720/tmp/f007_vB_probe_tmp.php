<?php
// vB: 保留提前 return，去嵌套改单层循环
class StringUtils {
    public static function levenshtein2(string $s1, string $s2): int {
        $len1 = strlen($s1);
        $len2 = strlen($s2);
        if ($len1 === 0) return $len2;
        if ($len2 === 0) return $len1;
        $sum = 0;
        for ($i = 1; $i <= $len1; $i++) { $sum += $i; }
        return $sum;
    }
}
echo "call1: " . StringUtils::levenshtein2('kitten', 'sitting') . "\n";
echo "=== done ===\n";
