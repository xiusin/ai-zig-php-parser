<?php
// vF: 提前return + 仅内层形态单层循环（体含数组写字段）
class StringUtils {
    public static function lev(string $s1, string $s2): int {
        $len1 = strlen($s1);
        $len2 = strlen($s2);
        if ($len1 === 0) return $len2;
        if ($len2 === 0) return $len1;
        $prev = range(0, $len2);
        $curr = [1];
        for ($j = 1; $j <= $len2; $j++) {
            $cost = $s1[0] === $s2[$j-1] ? 0 : 1;
            $curr[$j] = min($prev[$j] + 1, $curr[$j-1] + 1, $prev[$j-1] + $cost);
        }
        return $curr[$len2];
    }
}
echo "vF: " . StringUtils::lev('kitten', 'sitting') . "\n";
echo "=== done ===\n";
