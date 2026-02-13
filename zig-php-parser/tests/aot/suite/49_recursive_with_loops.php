<?php
// 测试: 递归函数中的深层循环
function recursive_loop($depth, $max_depth) {
    $result = "";
    if ($depth >= $max_depth) {
        return "[$depth]";
    }
    
    for ($i = 0; $i < 2; $i++) {
        for ($j = 0; $j < 2; $j++) {
            $result .= "$depth:$i$j ";
            if ($j == 0) {
                $result .= recursive_loop($depth + 1, $max_depth);
                break;
            }
        }
    }
    return $result;
}

echo recursive_loop(0, 3) . "\n";
