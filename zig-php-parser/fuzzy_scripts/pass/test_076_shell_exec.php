<?php
// 测试76: 执行外部命令的多种方式

// shell_exec
$whoami = shell_exec('whoami');
echo "Whoami: " . trim($whoami) . "\n";

// exec - 预声明变量避免警告
$output = [];
$return_code = 0;
exec('echo "Hello from exec"', $output, $return_code);
echo "Exec output: " . implode(" ", $output) . "\n";
echo "Return code: $return_code\n";

// system - 预声明变量
$return_var = 0;
$last_line = system('echo "System output"', $return_var);
echo "Last line: $last_line\n";
echo "System return: $return_var\n";

// 检查函数是否可用
$functions = ['exec', 'shell_exec', 'system'];
echo "Available functions:\n";
foreach ($functions as $fn) {
    echo "  $fn: " . (function_exists($fn) ? 'yes' : 'no') . "\n";
}
?>