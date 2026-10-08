<?php
// 永久探针（任务 #114 → 工单 AOT-CODEGEN-009，2026-10-07）：$字符串变量::class
// PHP 真值 = Fatal error: Uncaught TypeError: Cannot use "::class" on string（rc=255）
// 独立成文件的原因：该致命会终止进程，留在 c009_c 里会吞掉后续所有断言（实测如此）
class DAlpha {
}
$s = "DAlpha";
echo "str=" . $s::class . "\n";
echo "DONE\n";
