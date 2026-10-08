<?php
// f072 回归最小复现探针：if-return 前导 + 嵌套 cbr(ternary) 被 TRNEST2/CS0018 线性吞并
function inferArray(array $elements): string {
    if (empty($elements)) return 'array';
    $types = array_unique(array_map(fn($e) => gettype($e), $elements));
    $valType = count($types) === 1 ? $types[0] : 'mixed';
    return "array<$valType>";
}
echo inferArray([1, 2, 3]), "\n";
echo inferArray(['a', 'b']), "\n";
echo inferArray([1, 'a']), "\n";
echo inferArray([]), "\n";
