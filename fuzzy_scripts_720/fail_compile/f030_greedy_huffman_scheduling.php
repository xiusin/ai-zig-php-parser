<?php
// 极度混搭: 贪心算法 + 活动选择 + 哈夫曼编码 + 分零钱 + 区间调度
echo "=== f030: Greedy + Activity Selection + Huffman + Scheduling ===\n";

class Greedy {
    public static function activitySelection(array $start, array $finish): array {
        $n = count($start);
        $activities = [];
        for ($i = 0; $i < $n; $i++) {
            $activities[] = ['start' => $start[$i], 'finish' => $finish[$i], 'index' => $i];
        }
        usort($activities, fn($a, $b) => $a['finish'] <=> $b['finish']);

        $selected = [$activities[0]];
        $lastFinish = $activities[0]['finish'];

        for ($i = 1; $i < $n; $i++) {
            if ($activities[$i]['start'] >= $lastFinish) {
                $selected[] = $activities[$i];
                $lastFinish = $activities[$i]['finish'];
            }
        }
        return $selected;
    }

    public static function huffmanCodes(array $freqMap): array {
        $nodes = [];
        foreach ($freqMap as $char => $freq) {
            $nodes[] = ['char' => $char, 'freq' => $freq, 'left' => null, 'right' => null, 'code' => ''];
        }

        while (count($nodes) > 1) {
            usort($nodes, fn($a, $b) => $a['freq'] <=> $b['freq']);
            $left = array_shift($nodes);
            $right = array_shift($nodes);
            $merged = [
                'char' => null,
                'freq' => $left['freq'] + $right['freq'],
                'left' => $left,
                'right' => $right,
                'code' => '',
            ];
            $nodes[] = $merged;
        }

        $codes = [];
        self::generateHuffmanCodes($nodes[0], '', $codes);
        return $codes;
    }

    private static function generateHuffmanCodes(array $node, string $code, array &$codes): void {
        if ($node['char'] !== null) {
            $codes[$node['char']] = $code;
            return;
        }
        if ($node['left'] !== null) self::generateHuffmanCodes($node['left'], $code . '0', $codes);
        if ($node['right'] !== null) self::generateHuffmanCodes($node['right'], $code . '1', $codes);
    }

    public static function fractionalKnapsack(array $items, float $capacity): array {
        usort($items, fn($a, $b) => ($b['value'] / $b['weight']) <=> ($a['value'] / $a['weight']));

        $totalValue = 0.0;
        $result = [];

        foreach ($items as $item) {
            if ($capacity <= 0) break;
            $take = min($item['weight'], $capacity);
            $value = $item['value'] * ($take / $item['weight']);
            $totalValue += $value;
            $result[] = ['item' => $item['name'], 'weight' => $take, 'value' => $value];
            $capacity -= $take;
        }
        return ['total_value' => $totalValue, 'items' => $result];
    }

    public static function jobScheduling(array $jobs, int $deadline): array {
        usort($jobs, fn($a, $b) => $b['profit'] <=> $a['profit']);

        $slots = array_fill(0, $deadline, null);
        $totalProfit = 0;
        $scheduled = [];

        foreach ($jobs as $job) {
            $latest = min($job['deadline'], $deadline) - 1;
            for ($i = $latest; $i >= 0; $i--) {
                if ($slots[$i] === null) {
                    $slots[$i] = $job;
                    $totalProfit += $job['profit'];
                    $scheduled[] = $job;
                    break;
                }
            }
        }
        return ['profit' => $totalProfit, 'count' => count($scheduled), 'jobs' => $scheduled];
    }

    public static function gasStation(array $gas, array $cost): int {
        $totalGas = 0;
        $totalCost = 0;
        $tank = 0;
        $start = 0;

        for ($i = 0; $i < count($gas); $i++) {
            $totalGas += $gas[$i];
            $totalCost += $cost[$i];
            $tank += $gas[$i] - $cost[$i];
            if ($tank < 0) {
                $start = $i + 1;
                $tank = 0;
            }
        }
        return $totalGas >= $totalCost ? $start : -1;
    }

    public static function minCoins(array $coins, int $amount): array {
        rsort($coins);
        $result = [];
        $remaining = $amount;
        foreach ($coins as $coin) {
            while ($remaining >= $coin) {
                $result[] = $coin;
                $remaining -= $coin;
            }
        }
        return $remaining === 0 ? $result : [];
    }
}

// === 测试 ===
echo "--- Activity Selection ---\n";
$start =  [1, 3, 0, 5, 8, 5];
$finish = [2, 4, 6, 7, 9, 9];
$selected = Greedy::activitySelection($start, $finish);
echo "Activities: " . count($selected) . " selected\n";
foreach ($selected as $act) {
    echo "  Activity {$act['index']}: [{$act['start']}, {$act['finish']}]\n";
}

echo "\n--- Huffman Codes ---\n";
$frequencies = ['a' => 5, 'b' => 9, 'c' => 12, 'd' => 13, 'e' => 16, 'f' => 45];
$codes = Greedy::huffmanCodes($frequencies);
echo "Huffman codes:\n";
foreach ($codes as $char => $code) {
    echo "  '$char' (freq={$frequencies[$char]}): $code\n";
}

// 计算编码后的总长度
$totalBits = 0;
foreach ($frequencies as $char => $freq) {
    $totalBits += $freq * strlen($codes[$char]);
}
echo "Total bits: $totalBits\n";

echo "\n--- Fractional Knapsack ---\n";
$items = [
    ['name' => 'A', 'value' => 60, 'weight' => 10],
    ['name' => 'B', 'value' => 100, 'weight' => 20],
    ['name' => 'C', 'value' => 120, 'weight' => 30],
];
$result = Greedy::fractionalKnapsack($items, 50);
echo "Knapsack capacity=50:\n";
echo "  Total value: " . number_format($result['total_value'], 2) . "\n";
foreach ($result['items'] as $item) {
    echo "  {$item['item']}: weight=" . number_format($item['weight'], 1) . ", value=" . number_format($item['value'], 2) . "\n";
}

echo "\n--- Job Scheduling ---\n";
$jobs = [
    ['name' => 'J1', 'deadline' => 2, 'profit' => 100],
    ['name' => 'J2', 'deadline' => 1, 'profit' => 50],
    ['name' => 'J3', 'deadline' => 2, 'profit' => 20],
    ['name' => 'J4', 'deadline' => 1, 'profit' => 30],
    ['name' => 'J5', 'deadline' => 3, 'profit' => 80],
];
$result = Greedy::jobScheduling($jobs, 3);
echo "Scheduled {$result['count']} jobs, profit={$result['profit']}\n";
foreach ($result['jobs'] as $job) {
    echo "  {$job['name']}: deadline={$job['deadline']}, profit={$job['profit']}\n";
}

echo "\n--- Gas Station ---\n";
$gas =  [1, 2, 3, 4, 5];
$cost = [3, 4, 5, 1, 2];
$start = Greedy::gasStation($gas, $cost);
echo "Start index: $start\n";

$gas2 =  [2, 3, 4];
$cost2 = [3, 4, 3];
$start2 = Greedy::gasStation($gas2, $cost2);
echo "Start index (no solution): $start2\n";

echo "\n--- Min Coins (Greedy) ---\n";
$coins = [25, 10, 5, 1];
$result = Greedy::minCoins($coins, 67);
echo "Coins for 67: " . implode(', ', $result) . " (count=" . count($result) . ")\n";
$result2 = Greedy::minCoins($coins, 100);
echo "Coins for 100: " . implode(', ', $result2) . " (count=" . count($result2) . ")\n";

echo "=== f030 Done ===\n";
