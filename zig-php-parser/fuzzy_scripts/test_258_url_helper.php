<?php
function parseUrl2(string $url): array {
    $parsed = parse_url($url);
    $result = [
        'scheme' => $parsed['scheme'] ?? '',
        'host' => $parsed['host'] ?? '',
        'port' => $parsed['port'] ?? 0,
        'path' => $parsed['path'] ?? '',
        'query' => $parsed['query'] ?? '',
        'fragment' => $parsed['fragment'] ?? '',
    ];
    return $result;
}

function buildUrl(array $parts): string {
    $url = '';
    if (!empty($parts['scheme'])) $url .= $parts['scheme'] . '://';
    if (!empty($parts['host'])) $url .= $parts['host'];
    if (!empty($parts['port'])) $url .= ':' . $parts['port'];
    if (!empty($parts['path'])) $url .= $parts['path'];
    if (!empty($parts['query'])) $url .= '?' . $parts['query'];
    if (!empty($parts['fragment'])) $url .= '#' . $parts['fragment'];
    return $url;
}

function parseQueryString(string $query): array {
    parse_str($query, $params);
    return $params;
}

$url = 'https://example.com:8080/path/to/page?id=123&name=John#section';
$parsed = parseUrl2($url);
echo $parsed['scheme'] . "\n";
echo $parsed['host'] . "\n";
echo $parsed['path'] . "\n";

$params = parseQueryString('id=123&name=John');
echo $params['id'] . "\n";

$built = buildUrl(['scheme' => 'https', 'host' => 'test.com', 'path' => '/api']);
echo $built . "\n";
echo "OK\n";
