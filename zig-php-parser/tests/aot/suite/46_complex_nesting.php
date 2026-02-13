<?php
// 测试: 复杂嵌套（for + while + foreach + if）
function test_complex_nesting() {
    $result = "";
    $arr = [1, 2];
    
    for ($i = 0; $i < 2; $i++) {
        $j = 0;
        while ($j < 2) {
            foreach ($arr as $val) {
                if ($i == $j && $val == 1) {
                    $result .= "X ";
                    continue;
                }
                $result .= "$i$j$val ";
            }
            $j++;
        }
    }
    return $result;
}

echo test_complex_nesting() . "\n";
