<?php
// Comprehensive do-while loop tests
// Tests for AOT structured code generation of do-while loops

// Test 1: Basic do-while (executes until condition fails)
echo "Test 1: Basic do-while\n";
$i = 0;
do {
    echo $i . " ";
    $i++;
} while ($i < 5);
echo "\n";

// Test 2: do-while with exactly one iteration (condition false initially)
echo "Test 2: One iteration (body always executes)\n";
$x = 100;
do {
    echo "executed: $x\n";
    $x++;
} while ($x < 10);

// Test 3: do-while with break
echo "Test 3: do-while + break\n";
$j = 0;
do {
    echo $j . " ";
    $j++;
    if ($j >= 4) break;
} while ($j < 10);
echo "\n";

// Test 4: do-while with continue
echo "Test 4: do-while + continue\n";
$k = 0;
do {
    $k++;
    if ($k % 2 === 0) continue;
    echo $k . " ";
} while ($k < 10);
echo "\n";

// Test 5: do-while with sum accumulation
echo "Test 5: Summation\n";
$sum = 0;
$n = 1;
do {
    $sum += $n;
    $n++;
} while ($n <= 5);
echo "sum=$sum\n";

// Test 6: Nested do-while inside do-while
echo "Test 6: Nested do-while\n";
$outer = 0;
do {
    $inner = 0;
    do {
        echo "($outer,$inner) ";
        $inner++;
    } while ($inner < 2);
    echo "\n";
    $outer++;
} while ($outer < 3);

// Test 7: do-while with while inside
echo "Test 7: do-while with inner while\n";
$a = 0;
do {
    $b = 0;
    while ($b < 2) {
        echo "($a,$b) ";
        $b++;
    }
    echo "\n";
    $a++;
} while ($a < 3);

// Test 8: do-while with for inside
echo "Test 8: do-while with inner for\n";
$row = 0;
do {
    for ($col = 0; $col < 2; $col++) {
        echo "($row,$col) ";
    }
    echo "\n";
    $row++;
} while ($row < 3);

// Test 9: do-while with complex condition (logical AND)
echo "Test 9: Complex condition (AND)\n";
$v = 0;
$w = 100;
do {
    echo "v=$v\n";
    $v++;
    $w -= 30;
} while ($v < 3 && $w > 30);

// Test 10: do-while with complex condition (logical OR)
echo "Test 10: Complex condition (OR)\n";
$p = 0;
do {
    echo "p=$p\n";
    $p++;
} while ($p < 2 || $p > 10);

// Test 11: do-while modifying the condition variable inside loop
echo "Test 11: Modifying condition variable\n";
$count = 0;
do {
    $count += 2;
    echo "count=$count\n";
} while ($count < 7);

// Test 12: do-while with array operations
echo "Test 12: Array operations in do-while\n";
$arr = array();
$idx = 0;
do {
    $arr[] = $idx * 10;
    $idx++;
} while ($idx < 5);
echo "arr: " . implode(",", $arr) . "\n";

// Test 13: do-while with string operations
echo "Test 13: String operations in do-while\n";
$str = "";
$c = 0;
do {
    $str .= chr(65 + $c);
    $c++;
} while ($c < 5);
echo "str=$str\n";

// Test 14: do-while with function call in condition
echo "Test 14: Function call in condition\n";
function checkValue($val) { return $val <= 4; }
$val = 1;
do {
    echo "val=$val\n";
    $val++;
} while (checkValue($val));

// Test 15: Empty do-while body
echo "Test 15: Empty body\n";
$empty = 0;
do {
    $empty++;
} while ($empty < 3);
echo "empty=$empty\n";

// Test 16: do-while with early return simulation (break 2)
echo "Test 16: break from nested do-while\n";
$cnt = 0;
do {
    do {
        $cnt++;
        if ($cnt >= 3) break 2;
        echo "inner: $cnt\n";
    } while ($cnt < 10);
    echo "outer after inner\n";
} while ($cnt < 10);
echo "final cnt=$cnt\n";

// Test 17: do-while computing factorial
echo "Test 17: Factorial\n";
$fact = 1;
$num = 5;
do {
    $fact *= $num;
    $num--;
} while ($num > 0);
echo "5! = $fact\n";

// Test 18: Multiple do-while loops sequentially
echo "Test 18: Sequential do-while\n";
$s1 = 0;
do { echo "first: $s1 "; $s1++; } while ($s1 < 2);
echo "\n";
$s2 = 0;
do { echo "second: $s2 "; $s2++; } while ($s2 < 2);
echo "\n";

// Test 19: do-while with boolean variable condition
echo "Test 19: Boolean condition\n";
$cont = true;
$iter = 0;
do {
    echo "iter=$iter\n";
    $iter++;
    if ($iter >= 3) $cont = false;
} while ($cont);

// Test 20: do-while with decreasing counter
echo "Test 20: Decreasing counter\n";
$d = 5;
do {
    echo "$d ";
    $d--;
} while ($d > 0);
echo "\n";

// Test 21: do-while with if/else inside body
echo "Test 21: if/else in body\n";
$num_check = 0;
do {
    if ($num_check % 2 === 0) {
        echo "even: $num_check\n";
    } else {
        echo "odd: $num_check\n";
    }
    $num_check++;
} while ($num_check < 4);

// Test 22: Variable defined inside do-while used after
echo "Test 22: Variable scope\n";
do {
    $scoped = 42;
} while (false);
echo "scoped=$scoped\n";

echo "All do-while tests completed!\n";