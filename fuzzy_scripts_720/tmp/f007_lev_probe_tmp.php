<?php
// f007 levenshtein2 卡死最小复现探针
echo "A: range\n";
$prev = range(0, 7);
echo json_encode($prev) . "\n";

echo "B: min3\n";
echo min(3, 1, 2) . "\n";

echo "C: nested for with array build\n";
$s1 = "kitten"; $s2 = "sitting";
$len1 = strlen($s1); $len2 = strlen($s2);
$prev = range(0, $len2);
for ($i = 1; $i <= $len1; $i++) {
    $curr = [$i];
    for ($j = 1; $j <= $len2; $j++) {
        $cost = $s1[$i-1] === $s2[$j-1] ? 0 : 1;
        $curr[$j] = min($prev[$j] + 1, $curr[$j-1] + 1, $prev[$j-1] + $cost);
    }
    $prev = $curr;
}
echo "C result: " . $prev[$len2] . "\n";
echo "=== done ===\n";
