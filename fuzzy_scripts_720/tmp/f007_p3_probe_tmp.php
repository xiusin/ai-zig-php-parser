<?php
// f007 探针3：定位 提前return+循环 组合
class S {
    public static function withEarly(int $n): int {
        if ($n === 0) return 0;
        $sum = 0;
        for ($i = 1; $i <= $n; $i++) { $sum += $i; }
        return $sum;
    }
    public static function noEarly(int $n): int {
        $sum = 0;
        for ($i = 1; $i <= $n; $i++) { $sum += $i; }
        return $sum;
    }
    public static function twoEarly(int $n): int {
        if ($n === 0) return 0;
        if ($n === 1) return 1;
        $sum = 0;
        for ($i = 1; $i <= $n; $i++) { $sum += $i; }
        return $sum;
    }
}
echo "noEarly: " . S::noEarly(4) . "\n";
echo "twoEarly: " . S::twoEarly(4) . "\n";
echo "withEarly: " . S::withEarly(4) . "\n";
echo "=== done ===\n";
