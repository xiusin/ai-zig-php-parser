<?php
function escapeHtml(string $str): string {
    return htmlspecialchars($str, ENT_QUOTES | ENT_HTML5, 'UTF-8');
}

function escapeHtmlAttr(string $str): string {
    return htmlspecialchars($str, ENT_QUOTES | ENT_HTML5, 'UTF-8');
}

function escapeJs(string $str): string {
    return json_encode($str);
}

function escapeCss(string $str): string {
    return preg_replace('/[^a-zA-Z0-9_-]/', '', $str);
}

function escapeUrl(string $str): string {
    return urlencode($str);
}

function stripTags(string $str, string $allowable = ''): string {
    return strip_tags($str, $allowable);
}

$input = '<script>alert("XSS")</script>Hello <b>World</b>';
echo escapeHtml($input) . "\n";
echo stripTags($input, '<b>') . "\n";
echo escapeUrl('param=value&foo=bar') . "\n";
echo escapeJs('Hello "World"') . "\n";
echo "OK\n";
