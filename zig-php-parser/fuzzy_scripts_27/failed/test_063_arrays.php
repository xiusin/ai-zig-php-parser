<?php
// Test 063: Array functions - sort, search, merge
class ArrayFunctions {
    public function process(): string {
        $out = "";

        $nums = [3, 1, 4, 1, 5, 9, 2, 6];
        $out .= "Original: " . json_encode($nums) . "\n";

        $sorted = $nums;
        sort($sorted);
        $out .= "sort: " . json_encode($sorted) . "\n";

        $rsorted = $nums;
        rsort($rsorted);
        $out .= "rsort: " . json_encode($rsorted) . "\n";

        $assoc = ['c' => 3, 'a' => 1, 'b' => 2];
        $asorted = $assoc;
        asort($asorted);
        $out .= "asort: " . json_encode($asorted) . "\n";

        $ksorted = $assoc;
        ksort($ksorted);
        $out .= "ksort: " . json_encode($ksorted) . "\n";

        $usort = $nums;
        usort($usort, fn($a, $b) => $a <=> $b);
        $out .= "usort: " . json_encode($usort) . "\n";

        $uq = [1, 2, 2, 3, 3, 3];
        $out .= "array_unique: " . json_encode(array_unique($uq)) . "\n";

        $out .= "array_keys: " . json_encode(array_keys($assoc)) . "\n";
        $out .= "array_values: " . json_encode(array_values($assoc)) . "\n";

        $a1 = [1, 2, 3];
        $a2 = [4, 5, 6];
        $out .= "array_merge: " . json_encode(array_merge($a1, $a2)) . "\n";

        $out .= "array_slice([1,2,3,4,5], 1, 3): " . json_encode(array_slice([1,2,3,4,5], 1, 3)) . "\n";

        $splice = [1, 2, 3, 4, 5];
        array_splice($splice, 1, 2, ['x', 'y']);
        $out .= "array_splice [1,2 -> x,y]: " . json_encode($splice) . "\n";

        return $out;
    }
}

$lab = new ArrayFunctions();
echo $lab->process();

echo "\n=== Array search ===\n";
$arr = ['a', 'b', 'c', 'd'];
echo "array_search('c', \$arr): " . array_search('c', $arr) . "\n";
echo "in_array('b', \$arr): " . (in_array('b', $arr) ? 'yes' : 'no') . "\n";
echo "isset(\$arr[2]): " . (isset($arr[2]) ? 'yes' : 'no') . "\n";

echo "\n=== Array walk ===\n";
$data = ['a' => 1, 'b' => 2, 'c' => 3];
array_walk($data, function(&$value, $key) {
    $value *= 10;
});
echo "After walk (*10): " . json_encode($data) . "\n";

echo "\n=== Array reduce ===\n";
echo "array_reduce([1,2,3,4], +): " . array_reduce([1,2,3,4], fn($c, $v) => $c + $v, 0) . "\n";
echo "array_reduce(['a','b','c'], .): " . array_reduce(['a','b','c'], fn($c, $v) => $c . $v, '') . "\n";

echo "\n=== Array fill ===\n";
echo "array_fill(0, 5, 'x'): " . json_encode(array_fill(0, 5, 'x')) . "\n";
echo "range(1, 10): " . json_encode(range(1, 10)) . "\n";
echo "range('a', 'e'): " . json_encode(range('a', 'e')) . "\n";