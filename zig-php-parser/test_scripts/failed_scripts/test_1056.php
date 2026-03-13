<?php
// 错误抑制测试 2
$result = @file_get_contents("/nonexistent/path/file2.txt");
echo $result === false ? "suppressed" : "ok";
echo "
";
?>