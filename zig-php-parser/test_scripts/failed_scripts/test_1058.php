<?php
// 错误抑制测试 4
$result = @file_get_contents("/nonexistent/path/file4.txt");
echo $result === false ? "suppressed" : "ok";
echo "
";
?>