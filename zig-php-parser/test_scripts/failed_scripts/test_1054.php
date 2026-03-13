<?php
// 错误抑制测试 0
$result = @file_get_contents("/nonexistent/path/file0.txt");
echo $result === false ? "suppressed" : "ok";
echo "
";
?>