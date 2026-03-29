<?php
// Test 050: Spread operator in function calls, array merging
class SpreadLab {
    public function sum(int $a, int $b, int $c, int $d = 0, int $e = 0): int {
        return $a + $b + $c + $d + $e;
    }

    public function process(): string {
        $out = "";

        $nums = [1, 2, 3];
        $result = $this->sum(...$nums);
        $out .= "sum(...[1,2,3]): $result\n";

        $nums2 = [10, 20, 30, 40, 50];
        $result2 = $this->sum(...$nums2);
        $out .= "sum(...[10,20,30,40,50]): $result2\n";

        $partial = [100, 200];
        $result3 = call_user_func_array([$this, 'sum'], $partial);
        $result3 = $this->sum($partial[0], $partial[1], 5);
        $out .= "sum(100, 200, 5): $result3\n";

        return $out;
    }

    public function arraySpread(): string {
        $out = "";

        $base = [1, 2, 3];
        $added = array_merge($base, [4, 5, 6]);
        $out .= "Array merge: " . json_encode($added) . "\n";

        $prepended = array_merge([0], $base);
        $out .= "Prepend merge: " . json_encode($prepended) . "\n";

        $mid = array_merge([1], $base);
        array_push($mid, 4);
        $out .= "Mid merge: " . json_encode($mid) . "\n";

        $nested = [[1, 2], [3, 4]];
        $flat = array_merge(...$nested);
        $out .= "Array merge spread: " . json_encode($flat) . "\n";

        return $out;
    }

    public function variadic(): string {
        $out = "";

        function variadicFunc(int ...$args): int {
            return array_sum($args);
        }

        $out .= "variadicFunc(1,2,3,4,5): " . variadicFunc(1, 2, 3, 4, 5) . "\n";

        $nums = [10, 20, 30];
        $out .= "variadicFunc(...\$nums): " . variadicFunc(...$nums) . "\n";

        return $out;
    }
}

echo "=== Spread in function calls ===\n";
$lab = new SpreadLab();
echo $lab->process();

echo "\n=== Array spread ===\n";
echo $lab->arraySpread();

echo "\n=== Variadic ===\n";
echo $lab->variadic();

echo "\n=== Spread with named args ===\n";
function namedArgsFunc(string $name, int $age, bool $active = true): string {
    return "Name: $name, Age: $age, Active: " . ($active ? 'yes' : 'no');
}

$args = ['name' => 'Alice', 'age' => 30];
echo namedArgsFunc(...$args, active: false) . "\n";

echo "\n=== Keyed array merge ===\n";
$a = ['x' => 1, 'y' => 2];
$b = ['y' => 3, 'z' => 4];
$merged = array_merge(['first' => true], $a, $b);
echo "Keyed merge: " . json_encode($merged) . "\n";