<?php
// printf_capture测试 51
ob_start(); printf("%d", 123); echo ob_get_clean();
echo "
";
?>