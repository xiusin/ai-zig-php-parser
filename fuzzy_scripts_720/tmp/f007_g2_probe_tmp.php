<?php
// g2: vC 去掉两行提前 return（其余全保留：range/[$i]/$prev=$curr/嵌套/三元/min3）
class S {
    public static function f(string $s1, string $s2): int {
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
echo "g2: " . S::f('kitten', 'sitting') . "\n";
echo "=== done ===\n";
