<?php
echo "=== 字符串转义完整测试 ===\n\n";

$name = "张三";
$value = 100;

// 测试1: 基本变量插值
echo "【测试1】基本变量插值:\n";
echo "姓名: $name\n";
echo "值: $value\n\n";

// 测试2: 转义的美元符号
echo "【测试2】转义的美元符号:\n";
echo "\$name 应该显示 \$name\n";
echo "\$value = $value\n";
echo "价格: \$100 元\n\n";

// 测试3: 混合使用（关键测试）
echo "【测试3】混合使用转义和插值:\n";
echo "\$name = $name\n";
echo "\$value = $value 元\n";
echo "变量 \$name 的值是 $name，\$value 的值是 $value\n\n";

// 测试4: 连续转义
echo "【测试4】连续转义:\n";
echo "\\$name = $name\n";
echo "\\\$name = $name\n";
echo "\\\\$name = $name\n\n";

// 测试5: 其他转义序列
echo "【测试5】其他转义序列:\n";
echo "换行:\n第二行\n";
echo "制表:\t列2\t列3\n";
echo "反斜杠: \\ 单个反斜杠\n";
echo "双引号: \"引用\" 内容\n\n";

// 测试6: 反引号原始字符串
echo "【测试6】反引号原始字符串:\n";
$raw = `原始: $name \$value \n \t`;
echo $raw . "\n\n";

// 测试7: 单引号字符串
echo "【测试7】单引号字符串:\n";
echo '变量不插值: $name $value' . "\n";
echo '转义: \' 和 \\' . "\n\n";

echo "=== 所有测试完成 ===\n";
