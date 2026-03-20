<?php
function uuid4(): string {
    $data = random_bytes(16);
    $data[6] = chr(ord($data[6]) & 0x0f | 0x40);
    $data[8] = chr(ord($data[8]) & 0x3f | 0x80);
    return vsprintf('%s%s-%s-%s-%s-%s%s%s', str_split(bin2hex($data), 4));
}

function shortUuid(): string {
    return bin2hex(random_bytes(8));
}

function isValidUuid(string $uuid): bool {
    return preg_match('/^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i', $uuid) === 1;
}

function timestampUuid(): string {
    $time = microtime(true);
    $uuid = sprintf('%08x-%04x-%04x-%04x-%012f',
        (int)($time) & 0xffffffff,
        (int)(($time * 10000) % 0x10000),
        0x4000 | mt_rand(0, 0x0fff),
        0x8000 | mt_rand(0, 0x3fff),
        ($time - floor($time)) * 1000000000000
    );
    return $uuid;
}

$uuid = uuid4();
echo strlen($uuid) . "\n";
echo isValidUuid($uuid) ? 'true' : 'false' . "\n";
echo isValidUuid('invalid-uuid') ? 'true' : 'false' . "\n";
echo substr(shortUuid(), 0, 8) . "\n";
echo "OK\n";
