<?php
// 测试: do-while 嵌套 + break
function test_do_while_nested() {
    $result = "";
    $i = 0;
    do {
        $j = 0;
        do {
            $result .= "$i$j ";
            if ($j == 1) break;
            $j++;
        } while ($j < 3);
        $i++;
    } while ($i < 2);
    return $result;
}

echo test_do_while_nested() . "\n";
