<?php
// 测试: if-elseif 替代 switch
function test_switch($x) {
    if ($x == 1) {
        return "one";
    } elseif ($x == 2) {
        return "two";
    } elseif ($x == 3) {
        return "three";
    } else {
        return "other";
    }
}

echo test_switch(2) . "\n";
echo test_switch(5) . "\n";
