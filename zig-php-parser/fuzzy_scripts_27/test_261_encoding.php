<?php
function base64Encode2(string $data): string {
    return base64_encode($data);
}

function base64Decode2(string $data): string|false {
    return base64_decode($data);
}

function urlEncode2(string $data): string {
    return urlencode($data);
}

function urlDecode2(string $data): string {
    return urldecode($data);
}

function hexEncode(string $data): string {
    return bin2hex($data);
}

function hexDecode(string $data): string|false {
    return hex2bin($data);
}

$text = "Hello World! 你好世界";
$encoded = base64Encode2($text);
echo $encoded . "\n";
echo base64Decode2($encoded) . "\n";

$url = "param1=value1&param2=你好";
echo urlEncode2($url) . "\n";

$bin = "binary\x00data";
echo hexEncode($bin) . "\n";
echo hexDecode(hexEncode($bin)) . "\n";
echo "OK\n";
