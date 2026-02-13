<?php
// 测试: 5层深度嵌套 + 多层 break/continue
function test_deep_nesting() {
    $result = "";
    for ($a = 0; $a < 2; $a++) {
        for ($b = 0; $b < 2; $b++) {
            for ($c = 0; $c < 2; $c++) {
                for ($d = 0; $d < 2; $d++) {
                    for ($e = 0; $e < 2; $e++) {
                        $result .= "$a$b$c$d$e ";
                        if ($e == 1) break;
                        if ($d == 1 && $e == 0) break 2;
                        if ($c == 1 && $d == 0 && $e == 0) break 3;
                    }
                }
            }
        }
    }
    return $result;
}

echo test_deep_nesting() . "\n";
