<?php
// 永久探针（任务 #114 → 工单 AOT-CODEGEN-009，2026-10-07）：$对象变量::class（动态类名 ::class）
// PHP 8.0+ 允许 $obj::class；AOT 发射为 php_get_class_constant_dynamic(变量值, "class")
// 字符串变量那一形（PHP 侧直接 Fatal）已拆至 c009_d_str_class_tmp.php ⇒ 致命会吞掉同文件后续断言
// 直线语句、无 if/elseif 链 ⇒ 排除 CODEGEN-008 干扰
class VAlpha {
}
class VBravo extends VAlpha {
}

$o = new VBravo();
echo "obj=" . $o::class . "\n";
echo "lit=" . VBravo::class . "\n";
echo "dyn=" . get_class($o) . "\n";
echo "DONE\n";
