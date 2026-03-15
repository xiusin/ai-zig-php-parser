<?php
// 测试76: 执行外部命令的多种方式
// 注意：这些命令在大部分Unix系统上都可用

// shell_exec
$whoami = shell_exec('whoami');
echo "Whoami: " . trim($whoami) . "
";

// exec
exec('echo "Hello from exec"', $output, $return_code);
echo "Exec output: " . implode(" ", $output) . "
";
echo "Return code: $return_code
";

// passthru (直接输出到stdout)
echo "Passthru result: ";
// passthru('echo "passthru test"');
echo "
";

// system
$last_line = system('echo "System output"', $return_var);
echo "
Last line: $last_line
";

// proc_open (最灵活的方式)
$descriptors = [
    0 => ["pipe", "r"],  // stdin
    1 => ["pipe", "w"],  // stdout
    2 => ["pipe", "w"],  // stderr
];
$process = proc_open('cat', $descriptors, $pipes);
if (is_resource($process)) {
    fwrite($pipes[0], "Hello via proc_open");
    fclose($pipes[0]);
    $output = stream_get_contents($pipes[1]);
    fclose($pipes[1]);
    fclose($pipes[2]);
    proc_close($process);
    echo "Proc_open output: $output
";
}

// escapeshellarg
$unsafe = "; rm -rf /";
$safe = escapeshellarg($unsafe);
echo "Safe arg: $safe
";

// 检查函数是否可用
$functions = ['exec', 'shell_exec', 'system', 'passthru', 'proc_open'];
echo "Available functions:
";
foreach ($functions as $fn) {
    echo "  $fn: " . (function_exists($fn) ? 'yes' : 'no') . "
";
}
?>