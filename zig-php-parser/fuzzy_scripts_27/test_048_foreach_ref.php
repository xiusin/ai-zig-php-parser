<?php
// Test 048: Foreach by reference, list destructuring, and unpacking
class ForeachLab {
    public function process(): string {
        $out = "";

        $arr = [1, 2, 3, 4, 5];
        $byRef = [];
        foreach ($arr as &$value) {
            $value *= 2;
            $byRef[] = $value;
        }
        unset($value);
        $out .= "After foreach by ref, arr: " . json_encode($arr) . "\n";

        $original = ['a', 'b', 'c'];
        $copy = [];
        foreach ($original as &$item) {
            $copy[] = &$item;
        }
        unset($item);
        $copy[0] = 'modified';
        $out .= "Original after copy modify: " . json_encode($original) . "\n";

        return $out;
    }

    public function listDestruct(): string {
        $out = "";

        $point = [10, 20];
        [$x, $y] = $point;
        $out .= "List destructure: x=$x, y=$y\n";

        $nested = [[1, 2], [3, 4]];
        [[$a, $b], [$c, $d]] = $nested;
        $out .= "Nested destructure: a=$a, b=$b, c=$c, d=$d\n";

        $head = [1, 2, 3, 4, 5];
        $first = $head[0];
        $second = $head[1];
        $rest = array_slice($head, 2);
        $out .= "Manual spread dest: first=$first, second=$second, rest=" . json_encode($rest) . "\n";

        $arr = ['a' => 1, 'b' => 2, 'c' => 3];
        $x = $arr['a'];
        $y = $arr['b'];
        $z = $arr['c'];
        $out .= "Key destructure: x=$x, y=$y, z=$z\n";

        return $out;
    }

    public function arrayUnpacking(): string {
        $out = "";

        $a = [1, 2, 3];
        $b = [4, 5, 6];
        $merged = array_merge($a, $b);
        $out .= "Array merge: " . json_encode($merged) . "\n";

        $head = array_merge([0], $a);
        array_push($head, 10);
        $out .= "Manual middle: " . json_encode($head) . "\n";

        return $out;
    }
}

echo "=== Foreach by reference ===\n";
$lab = new ForeachLab();
echo $lab->process();

echo "\n=== List destructuring ===\n";
echo $lab->listDestruct();

echo "\n=== Array unpacking ===\n";
echo $lab->arrayUnpacking();

echo "\n=== Foreach with keys ===\n";
$arr = ['a' => 1, 'b' => 2, 'c' => 3];
foreach ($arr as $key => &$value) {
    $value *= 10;
}
unset($value);
echo "After key ref: " . json_encode($arr) . "\n";

echo "\n=== Foreach with list ===\n";
$pairs = [[1, 'one'], [2, 'two'], [3, 'three']];
foreach ($pairs as list($num, $str)) {
    echo "num=$num, str=$str\n";
}

echo "\n=== Array spread with keys ===\n";
$a = ['x' => 1, 'y' => 2];
$b = array_merge($a, ['z' => 3]);
echo "Spread with keys: " . json_encode($b) . "\n";