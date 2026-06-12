<?php
// 输出缓冲测试

// 基础输出缓冲
ob_start();
echo "This is buffered";
$buffered = ob_get_clean();
echo "Buffered content: $buffered\n";

// 嵌套缓冲
ob_start();
echo "Outer buffer";

ob_start();
echo " - Inner buffer";
$inner = ob_get_clean();

$outer = ob_get_clean();
echo "Outer: $outer\n";
echo "Inner: $inner\n";

// 缓冲级别
echo "Initial level: " . ob_get_level() . "\n";

ob_start();
echo "Level after start: " . ob_get_level() . "\n";
ob_end_clean();
echo "Level after clean: " . ob_get_level() . "\n";

// 缓冲状态
ob_start();
$status = ob_get_status();
echo "Status name: " . $status['name'] . "\n";
ob_end_clean();

// 缓冲回调
ob_start(function($buffer) {
    return strtoupper($buffer);
});
echo "lowercase content";
$result = ob_get_clean();
echo "Uppercased: $result\n";

// 缓冲刷新
ob_start();
echo "To be flushed";
// ob_flush() 会输出内容
ob_end_clean();

// 缓冲长度
ob_start();
echo "12345";
$len = ob_get_length();
ob_end_clean();
echo "Buffer length was: $len\n";

// 缓冲内容获取
ob_start();
echo "Content A";
$content1 = ob_get_contents();
echo " + Content B";
$content2 = ob_get_contents();
ob_end_clean();
echo "Content1: $content1\n";
echo "Content2: $content2\n";

// 多级缓冲清理
ob_start();
ob_start();
ob_start();
echo "Nested buffers: " . ob_get_level() . "\n";
while (ob_get_level() > 0) {
    ob_end_clean();
}
echo "All cleaned, level: " . ob_get_level() . "\n";

// 条件缓冲
function conditionalBuffer(bool $enabled): string {
    if ($enabled) ob_start();
    echo "Conditional output";
    if ($enabled) return ob_get_clean();
    return "not buffered";
}

$buffered = conditionalBuffer(true);
echo "Conditional: $buffered\n";

// 缓冲作为模板
function renderTemplate(string $template, array $vars): string {
    extract($vars);
    ob_start();
    eval("?>" . $template);
    return ob_get_clean();
}

$template = '<?php echo $name; ?> is <?php echo $age; ?> years old';
$result = renderTemplate($template, ['name' => 'Alice', 'age' => 25]);
echo "Template result: $result\n";

// gzhandler (需要zlib扩展)
if (function_exists('ob_gzhandler')) {
    echo "gzhandler available\n";
} else {
    echo "gzhandler not available\n";
}

echo "Output buffering tests completed\n";
