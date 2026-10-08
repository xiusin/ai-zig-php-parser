<?php
// vA: 去掉两行提前 return
class StringUtils {
    public static function levenshtein2(string $s1, string $s2): int {
        $len1 = strlen($s1);
        $len2 = strlen($s2);
        $prev = range(0, $len2);
        for ($i = 1; $i <= $len1; $i++) {
            $curr = [$i];
            for ($j = 1; $j <= $len2; $j++) {
                $cost = $s1[$i-1] === $s2[$j-1] ? 0 : 1;
                $curr[$j] = min($prev[$j] + 1, $curr[$j-1] + 1, $prev[$j-1] + $cost);
            }
            $prev = $curr;
        }
        return $prev[$len2];
    }
}
echo "call1: " . StringUtils::levenshtein2('kitten', 'sitting') . "\n";
echo "=== done ===\n";
