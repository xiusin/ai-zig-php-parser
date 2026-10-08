<?php
// g3: 提前return + 嵌套双层 + 外层尾 $prev=$curr 数组整体拷贝
class S {
    public static function f(string $s1, string $s2): int {
        $len1 = strlen($s1);
        if ($len1 === 0) return 0;
        $len2 = strlen($s2);
        $prev = range(0, $len2);
        for ($i = 1; $i <= $len1; $i++) {
            $curr = [$i];
            for ($j = 1; $j <= $len2; $j++) { $curr[$j] = $j; }
            $prev = $curr;
        }
        return $prev[$len2];
    }
}
echo "g3: " . S::f('kitten', 'sitting') . "\n";
echo "=== done ===\n";
