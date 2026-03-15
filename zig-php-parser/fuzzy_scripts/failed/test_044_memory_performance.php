<?php
// 测试44: 内存管理与性能
$start = microtime(true);

// 大量对象创建
$objects = [];
for ($i = 0; $i < 100; $i++) {
    $objects[] = new stdClass();
}
unset($objects);

// 大量字符串操作
$str = "";
for ($i = 0; $i < 100; $i++) {
    $str .= str_repeat("x", 10);
}
echo "String length: " . strlen($str) . "\n";
unset($str);

// 内存峰值
echo "Peak memory: " . memory_get_peak_usage() . " bytes\n";
echo "Current memory: " . memory_get_usage() . " bytes\n";

// 垃圾回收
gc_enable();
$cycles = gc_collect_cycles();
echo "Collected cycles: $cycles\n";

// 循环引用垃圾回收
$a = new stdClass();
$b = new stdClass();
$a->ref = $b;
$b->ref = $a;
unset($a, $b);

$cycles2 = gc_collect_cycles();
echo "Collected cycles after circular ref: $cycles2\n";

// 资源使用
$end = microtime(true);
echo "Execution time: " . ($end - $start) . " seconds\n";

// getrusage (Unix系统)
if (function_exists("getrusage")) {
    $usage = getrusage();
    echo "User time: " . $usage["ru_utime.tv_sec"] . "\n";
}

// 内存限制
$limit = ini_get("memory_limit");
echo "Memory limit: $limit\n";
?>
