<?php
// 错误抑制测试 3
$result = @file_get_contents("/nonexistent/path/file3.txt");
echo $result === false ? "suppressed" : "ok";
echo "
";
?>