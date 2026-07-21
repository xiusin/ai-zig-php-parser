<?php
// 极度混搭: 动态规划 + 背包 + LCS + 最长递增子序列 + 编辑距离
echo "=== f028: DP + Knapsack + LCS + LIS + EditDistance ===\n";

class DynamicProgramming {
    public static function knapsack01(array $weights, array $values, int $capacity): array {
        $n = count($weights);
        $dp = array_fill(0, $capacity + 1, 0);
        $keep = array_fill(0, $n, array_fill(0, $capacity + 1, false));

        for ($i = 0; $i < $n; $i++) {
            for ($w = $capacity; $w >= $weights[$i]; $w--) {
                if ($dp[$w - $weights[$i]] + $values[$i] > $dp[$w]) {
                    $dp[$w] = $dp[$w - $weights[$i]] + $values[$i];
                    $keep[$i][$w] = true;
                }
            }
        }

        $items = [];
        $w = $capacity;
        for ($i = $n - 1; $i >= 0; $i--) {
            if ($keep[$i][$w]) {
                $items[] = $i;
                $w -= $weights[$i];
            }
        }
        return ['value' => $dp[$capacity], 'items' => array_reverse($items)];
    }

    public static function lcs(string $s1, string $s2): array {
        $m = strlen($s1);
        $n = strlen($s2);
        $dp = array_fill(0, $m + 1, array_fill(0, $n + 1, 0));

        for ($i = 1; $i <= $m; $i++) {
            for ($j = 1; $j <= $n; $j++) {
                if ($s1[$i-1] === $s2[$j-1]) {
                    $dp[$i][$j] = $dp[$i-1][$j-1] + 1;
                } else {
                    $dp[$i][$j] = max($dp[$i-1][$j], $dp[$i][$j-1]);
                }
            }
        }

        // Backtrack to find the LCS string
        $result = '';
        $i = $m; $j = $n;
        while ($i > 0 && $j > 0) {
            if ($s1[$i-1] === $s2[$j-1]) {
                $result = $s1[$i-1] . $result;
                $i--; $j--;
            } elseif ($dp[$i-1][$j] >= $dp[$i][$j-1]) {
                $i--;
            } else {
                $j--;
            }
        }
        return ['length' => $dp[$m][$n], 'sequence' => $result];
    }

    public static function lis(array $arr): array {
        $n = count($arr);
        if ($n === 0) return ['length' => 0, 'sequence' => []];

        $dp = array_fill(0, $n, 1);
        $prev = array_fill(0, $n, -1);

        for ($i = 1; $i < $n; $i++) {
            for ($j = 0; $j < $i; $j++) {
                if ($arr[$j] < $arr[$i] && $dp[$j] + 1 > $dp[$i]) {
                    $dp[$i] = $dp[$j] + 1;
                    $prev[$i] = $j;
                }
            }
        }

        $maxLen = 0; $maxIdx = 0;
        for ($i = 0; $i < $n; $i++) {
            if ($dp[$i] > $maxLen) { $maxLen = $dp[$i]; $maxIdx = $i; }
        }

        $sequence = [];
        $idx = $maxIdx;
        while ($idx >= 0) {
            array_unshift($sequence, $arr[$idx]);
            $idx = $prev[$idx];
        }
        return ['length' => $maxLen, 'sequence' => $sequence];
    }

    public static function editDistance(string $s1, string $s2): int {
        $m = strlen($s1);
        $n = strlen($s2);
        $dp = [];
        for ($i = 0; $i <= $m; $i++) $dp[$i] = [$i];
        for ($j = 0; $j <= $n; $j++) $dp[0][$j] = $j;

        for ($i = 1; $i <= $m; $i++) {
            for ($j = 1; $j <= $n; $j++) {
                $cost = $s1[$i-1] === $s2[$j-1] ? 0 : 1;
                $dp[$i][$j] = min($dp[$i-1][$j] + 1, $dp[$i][$j-1] + 1, $dp[$i-1][$j-1] + $cost);
            }
        }
        return $dp[$m][$n];
    }

    public static function coinChange(array $coins, int $amount): array {
        $dp = array_fill(0, $amount + 1, PHP_INT_MAX);
        $dp[0] = 0;
        $used = array_fill(0, $amount + 1, -1);

        for ($i = 1; $i <= $amount; $i++) {
            foreach ($coins as $coin) {
                if ($coin <= $i && $dp[$i - $coin] + 1 < $dp[$i]) {
                    $dp[$i] = $dp[$i - $coin] + 1;
                    $used[$i] = $coin;
                }
            }
        }

        if ($dp[$amount] === PHP_INT_MAX) return ['count' => -1, 'coins' => []];

        $result = [];
        $remaining = $amount;
        while ($remaining > 0) {
            $coin = $used[$remaining];
            $result[] = $coin;
            $remaining -= $coin;
        }
        return ['count' => $dp[$amount], 'coins' => $result];
    }

    public static function maxSubArray(array $arr): array {
        $n = count($arr);
        if ($n === 0) return ['sum' => 0, 'start' => 0, 'end' => 0];

        $maxSum = $arr[0]; $currentSum = $arr[0];
        $start = 0; $end = 0; $tempStart = 0;

        for ($i = 1; $i < $n; $i++) {
            if ($currentSum + $arr[$i] < $arr[$i]) {
                $currentSum = $arr[$i];
                $tempStart = $i;
            } else {
                $currentSum += $arr[$i];
            }
            if ($currentSum > $maxSum) {
                $maxSum = $currentSum;
                $start = $tempStart;
                $end = $i;
            }
        }
        return ['sum' => $maxSum, 'start' => $start, 'end' => $end];
    }
}

// === 测试 ===
echo "--- 0/1 Knapsack ---\n";
$weights = [2, 3, 4, 5];
$values = [3, 4, 5, 6];
$cap = 8;
$result = DynamicProgramming::knapsack01($weights, $values, $cap);
echo "Weights: " . implode(',', $weights) . " Values: " . implode(',', $values) . " Cap: $cap\n";
echo "Max value: {$result['value']}, Items: " . implode(',', $result['items']) . "\n";

echo "\n--- LCS ---\n";
$r = DynamicProgramming::lcs("ABCBDAB", "BDCAB");
echo "LCS('ABCBDAB', 'BDCAB'): length={$r['length']}, seq='{$r['sequence']}'\n";
$r2 = DynamicProgramming::lcs("AGGTAB", "GXTXAYB");
echo "LCS('AGGTAB', 'GXTXAYB'): length={$r2['length']}, seq='{$r2['sequence']}'\n";

echo "\n--- LIS ---\n";
$arr = [10, 9, 2, 5, 3, 7, 101, 18];
$r = DynamicProgramming::lis($arr);
echo "LIS(" . implode(',', $arr) . "): length={$r['length']}, seq=[" . implode(',', $r['sequence']) . "]\n";
$arr2 = [0, 1, 0, 3, 2, 3];
$r2 = DynamicProgramming::lis($arr2);
echo "LIS(" . implode(',', $arr2) . "): length={$r2['length']}, seq=[" . implode(',', $r2['sequence']) . "]\n";

echo "\n--- Edit Distance ---\n";
echo "editDistance('kitten', 'sitting') = " . DynamicProgramming::editDistance('kitten', 'sitting') . "\n";
echo "editDistance('sunday', 'saturday') = " . DynamicProgramming::editDistance('sunday', 'saturday') . "\n";
echo "editDistance('abc', 'abc') = " . DynamicProgramming::editDistance('abc', 'abc') . "\n";

echo "\n--- Coin Change ---\n";
$coins = [1, 5, 10, 25];
$r = DynamicProgramming::coinChange($coins, 63);
echo "Coins(" . implode(',', $coins) . ") Amount=63: count={$r['count']}, coins=[" . implode(',', $r['coins']) . "]\n";
$r2 = DynamicProgramming::coinChange([2, 5, 7], 13);
echo "Coins(2,5,7) Amount=13: count={$r2['count']}, coins=[" . implode(',', $r2['coins']) . "]\n";

echo "\n--- Max SubArray ---\n";
$arr = [-2, 1, -3, 4, -1, 2, 1, -5, 4];
$r = DynamicProgramming::maxSubArray($arr);
echo "MaxSubArray(" . implode(',', $arr) . "): sum={$r['sum']}, range=[{$r['start']},{$r['end']}]\n";
$arr2 = [1, 2, 3, -1, 4, -2, 5];
$r2 = DynamicProgramming::maxSubArray($arr2);
echo "MaxSubArray(" . implode(',', $arr2) . "): sum={$r2['sum']}, range=[{$r2['start']},{$r2['end']}]\n";

echo "=== f028 Done ===\n";
