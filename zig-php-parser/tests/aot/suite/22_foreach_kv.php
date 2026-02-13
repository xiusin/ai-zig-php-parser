<?php
// 测试: foreach with key-value
function test_foreach_kv() {
    $arr = ["a" => 1, "b" => 2, "c" => 3];
    $result = "";
    foreach ($arr as $key => $val) {
        $result = $result . $key . $val;
    }
    return $result;
}

echo test_foreach_kv() . "\n";
