<?php
// 测试: 函数调用中的深层流程嵌套
function inner_loop($prefix) {
    $result = "";
    for ($i = 0; $i < 2; $i++) {
        $result .= "$prefix:$i ";
        if ($i == 0) break;
    }
    return $result;
}

function outer_loop() {
    $result = "";
    for ($n = 0; $n < 2; $n++) {
        $result .= inner_loop("N$n");
        for ($m = 0; $m < 2; $m++) {
            $result .= "[$n-$m] ";
            if ($m == 0) break;
        }
    }
    return $result;
}

echo outer_loop() . "\n";
