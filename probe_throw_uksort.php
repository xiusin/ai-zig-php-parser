<?php
$a = ['b'=>3, 'a'=>1, 'c'=>2, 'e'=>5, 'd'=>4];
$calls = 0;
try {
    uksort($a, function($x, $y) use (&$calls) {
        $calls++;
        if ($calls >= 3) throw new Exception("boom");
        return strcmp($x, $y);
    });
} catch (Exception $e) {
    echo "caught: ", $e->getMessage(), "\n";
}
echo "calls=$calls\n";
echo json_encode($a), "\n";
ksort($a);
echo json_encode($a), "\n";
