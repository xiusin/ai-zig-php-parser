<?php
// 测试: 混合控制流（switch + foreach + while）
function test_mixed_control() {
    $result = "";
    $arr = [1, 2, 3];
    
    foreach ($arr as $val) {
        switch ($val) {
            case 1:
                $i = 0;
                while ($i < 2) {
                    $result .= "1w$i ";
                    $i++;
                }
                break;
            case 2:
                for ($j = 0; $j < 2; $j++) {
                    $result .= "2f$j ";
                }
                break;
            default:
                $result .= "3d ";
        }
    }
    return $result;
}

echo test_mixed_control() . "\n";
