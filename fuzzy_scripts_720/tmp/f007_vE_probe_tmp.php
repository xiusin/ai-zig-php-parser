<?php
// vE: 提前return + 仅外层循环（无内层）
class StringUtils {
    public static function lev(string $s1, string $s2): int {
        $len1 = strlen($s1);
        $len2 = strlen($s2);
        if ($len1 === 0) return $len2;
        if ($len2 === 0) return $len1;
        $prev = range(0, $len2);
        for ($i = 1; $i <= $len1; $i++) {
            $curr = [$i];
            $prev = $curr;
        }
        return count($prev);
    }
}
echo "vE: " . StringUtils::lev('kitten', 'sitting') . "\n";
echo "=== done ===\n";
