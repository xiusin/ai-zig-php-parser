<?php
function arrayFill2(int $count, mixed $value): array {
    return array_fill(0, $count, $value);
}

function arrayRepeat(array $arr, int $times): array {
    $result = [];
    for ($i = 0; $i < $times; $i++) {
        foreach ($arr as $v) {
            $result[] = $v;
        }
    }
    return $result;
}

function arrayCompact(array $arr): array {
    return array_filter($arr, fn($v) => $v !== null && $v !== '');
}

function arrayFlattenOnce(array $arr): array {
    $result = [];
    foreach ($arr as $v) {
        if (is_array($v)) {
            foreach ($v as $item) {
                $result[] = $item;
            }
        } else {
            $result[] = $v;
        }
    }
    return $result;
}

print_r(arrayFill2(5, 'x'));
print_r(arrayRepeat([1, 2], 3));
print_r(arrayCompact(['a', null, 'b', '', 'c']));
print_r(arrayFlattenOnce([[1, 2], [3, 4], 5]));
echo "OK\n";
