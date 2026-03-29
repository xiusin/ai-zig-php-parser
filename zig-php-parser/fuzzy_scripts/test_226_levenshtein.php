<?php
function levenshteinDistance(string $a, string $b): int {
    $m = strlen($a);
    $n = strlen($b);

    if ($m === 0) return $n;
    if ($n === 0) return $m;

    $dp = array_fill(0, $m + 1, array_fill(0, $n + 1, 0));

    for ($i = 0; $i <= $m; $i++) $dp[$i][0] = $i;
    for ($j = 0; $j <= $n; $j++) $dp[0][$j] = $j;

    for ($i = 1; $i <= $m; $i++) {
        for ($j = 1; $j <= $n; $j++) {
            $cost = $a[$i - 1] === $b[$j - 1] ? 0 : 1;
            $dp[$i][$j] = min(
                $dp[$i - 1][$j] + 1,
                $dp[$i][$j - 1] + 1,
                $dp[$i - 1][$j - 1] + $cost
            );
        }
    }

    return $dp[$m][$n];
}

echo levenshteinDistance('kitten', 'sitting') . "\n";
echo levenshteinDistance('flaw', 'lawn') . "\n";
echo levenshteinDistance('PHP', 'php') . "\n";
echo levenshteinDistance('', 'abc') . "\n";
echo levenshteinDistance('same', 'same') . "\n";
echo "OK\n";
