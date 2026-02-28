<?php

function fib($n) {
    if ($n <= 1) return $n;
    return fib($n - 1) + fib($n - 2);
}
$result = 0;
for ($i = 0; $i < 10; $i++) {
    $result += fib($i);
}
echo $result;

?>
