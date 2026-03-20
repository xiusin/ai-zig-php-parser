<?php
function generateSubsets(array $arr, int $k): array {
    $result = [];
    $n = count($arr);

    function generate(int $index, array $current) use ($arr, $n, $k, &$result) {
        if (count($current) === $k) {
            $result[] = $current;
            return;
        }
        if ($index >= $n) return;

        for ($i = $index; $i < $n; $i++) {
            $current[] = $arr[$i];
            generate($i + 1, $current);
            array_pop($current);
        }
    }

    generate(0, []);
    return $result;
}

function generatePermutations(array $arr): array {
    if (count($arr) <= 1) return [$arr];

    $result = [];
    foreach ($arr as $i => $item) {
        $remaining = $arr;
        unset($remaining[$i]);
        foreach (generatePermutations(array_values($remaining)) as $perm) {
            array_unshift($perm, $item);
            $result[] = $perm;
        }
    }

    return $result;
}

$subsets = generateSubsets([1, 2, 3], 2);
echo count($subsets) . "\n";
foreach ($subsets as $s) {
    echo implode(',', $s) . " ";
}
echo "\n";

$perms = generatePermutations([1, 2, 3]);
echo count($perms) . "\n";
echo "OK\n";
