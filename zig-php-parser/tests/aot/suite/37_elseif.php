<?php
// 测试: elseif
function test_elseif($x) {
    if ($x < 0) {
        return "negative";
    } elseif ($x == 0) {
        return "zero";
    } elseif ($x < 10) {
        return "small";
    } else {
        return "large";
    }
}

echo test_elseif(-5) . "\n";
echo test_elseif(0) . "\n";
echo test_elseif(5) . "\n";
echo test_elseif(15) . "\n";
