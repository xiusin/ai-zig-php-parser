<?php
// 测试26: 网络与Socket测试
// 测试DNS解析
$hosts = ['localhost', '127.0.0.1'];
foreach ($hosts as $host) {
    $ip = gethostbyname($host);
    $name = gethostbyaddr($ip);
    echo "Host: $host -> IP: $ip -> Name: $name\n";
}

// 获取本机信息
echo "Server name: " . gethostname() . "\n";

// 解析URL
$url = "https://user:pass@example.com:8080/path?query=value#fragment";
$parts = parse_url($url);
echo "URL parts:\n";
print_r($parts);

// 编码URL
$encoded = urlencode("hello world!@#$%");
$decoded = urldecode($encoded);
echo "Encoded: $encoded\n";
echo "Decoded: $decoded\n";

// Base64 URL safe
$data = "Hello+World/Test=";
$base64 = base64_encode($data);
$decoded64 = base64_decode($base64);
echo "Base64: $base64\n";
echo "Decoded64: $decoded64\n";

// 网络字节序
$hostLong = 123456789;
$netLong = htonl($hostLong);
$backToHost = ntohl($netLong);
echo "Host: $hostLong, Network: $netLong, Back: $backToHost\n";

// IP验证与转换
$ip = "192.168.1.1";
$longIp = ip2long($ip);
$backIp = long2ip($longIp);
echo "IP: $ip, Long: $longIp, Back: $backIp\n";

echo "IP validate (192.168.1.1): " . (filter_var("192.168.1.1", FILTER_VALIDATE_IP) ? "valid" : "invalid") . "\n";
echo "IP validate (invalid): " . (filter_var("invalid", FILTER_VALIDATE_IP) ? "valid" : "invalid") . "\n";

// HTTP headers解析模拟
$headers = [
    "Content-Type: application/json",
    "Authorization: Bearer token123",
    "X-Custom-Header: value"
];

foreach ($headers as $header) {
    if (strpos($header, ':') !== false) {
        list($key, $value) = explode(':', $header, 2);
        echo "Header: " . trim($key) . " => " . trim($value) . "\n";
    }
}

// 检查扩展
$extensions = ['sockets', 'curl', 'openssl'];
foreach ($extensions as $ext) {
    echo "Extension $ext: " . (extension_loaded($ext) ? "loaded" : "not loaded") . "\n";
}
?>
