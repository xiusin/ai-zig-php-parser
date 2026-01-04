<?php
// 通过函数名调用
$func = "strlen";
$result = call_user_func($func, "Hello");

// 通过回调数组调用
$result = call_user_func([$obj, "method"], $arg1, $arg2);

// 通过数组传递参数
$result = call_user_func_array("array_sum", [[1, 2, 3]]);

print_r($result);