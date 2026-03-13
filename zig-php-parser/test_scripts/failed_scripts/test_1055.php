<?php
// 错误抑制测试 1
$result = @file_get_contents("/nonexistent/path/file1.txt");
echo $result === false ? "suppressed" : "ok";
echo "
";
?>