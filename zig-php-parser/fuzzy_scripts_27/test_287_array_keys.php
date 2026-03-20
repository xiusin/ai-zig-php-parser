<?php
function arrayKeyExists2(array $arr, int|string $key): bool {
    return array_key_exists($key, $arr);
}

function arrayKeys2(array $arr): array {
    return array_keys($arr);
}

function arrayValues2(array $arr): array {
    return array_values($arr);
}

function arrayEntries(array $arr): array {
    $result = [];
    foreach ($arr as $k => $v) {
        $result[] = [$k, $v];
    }
    return $result;
}

function arrayFlip(array $arr): array {
    return array_flip($arr);
}

$arr = ['a' => 1, 'b' => 2, 'c' => 3];
echo arrayKeyExists2($arr, 'b') ? 'true' : 'false' . "\n";
echo implode(',', arrayKeys2($arr)) . "\n";
echo implode(',', arrayValues2($arr)) . "\n";
echo count(arrayEntries($arr)) . "\n";
echo implode(',', array_keys(arrayFlip($arr))) . "\n";
echo "OK\n";
