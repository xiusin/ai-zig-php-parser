<?php
// g1: withEarly 形态 + 内层只加计数（标量），带提前return
class S {
    public static function f(string $s1, string $s2): int {
        $len1 = strlen($s1);
        if ($len1 === 0) return 0;
        $sum = 0;
        for ($i = 1; $i <= $len1; $i++) {
            for ($j = 1; $j <= 7; $j++) { $sum += 1; }
        }
        return $sum;
    }
}
echo "g1: " . S::f('kitten', 'sitting') . "\n";
echo "=== done ===\n";
