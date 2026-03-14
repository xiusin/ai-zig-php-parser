<?php
// printf_capture测试 20
ob_start(); printf("%d", 123); echo ob_get_clean();
echo "
";
?>