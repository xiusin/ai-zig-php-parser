<?php
// 测试45: 流与过滤器
$data = "Hello World! This is test data.";

// 临时流
$temp = fopen("php://temp", "r+");
fwrite($temp, $data);
rewind($temp);
$read = fread($temp, 1024);
echo "From temp stream: $read\n";
fclose($temp);

// 内存流
$memory = fopen("php://memory", "r+");
fwrite($memory, $data);
rewind($memory);
$content = stream_get_contents($memory);
echo "From memory stream: " . strlen($content) . " bytes\n";
fclose($memory);

// 输入输出流 (只检查是否存在)
echo "STDIN defined: " . (defined("STDIN") ? "yes" : "no") . "\n";
echo "STDOUT defined: " . (defined("STDOUT") ? "yes" : "no") . "\n";
echo "STDERR defined: " . (defined("STDERR") ? "yes" : "no") . "\n";

// 流元数据
$temp2 = fopen("php://temp", "r+");
write($temp2, "test");
$meta = stream_get_meta_data($temp2);
echo "Stream metadata:\n";
print_r($meta);
fclose($temp2);

// 字符串编码转换
if (function_exists("iconv")) {
    $utf8 = "Hello World";
    $gbk = @iconv("UTF-8", "GBK", $utf8);
    echo "Iconv available: yes\n";
} else {
    echo "Iconv available: no\n";
}

if (function_exists("mb_convert_encoding")) {
    echo "MBString available: yes\n";
} else {
    echo "MBString available: no\n";
}

// 压缩流
if (extension_loaded("zlib")) {
    echo "Zlib available: yes\n";
    $compressed = gzencode("test data");
    echo "Compressed size: " . strlen($compressed) . "\n";
} else {
    echo "Zlib available: no\n";
}
?>
