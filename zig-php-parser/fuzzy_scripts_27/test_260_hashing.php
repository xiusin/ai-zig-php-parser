<?php
function md5Hash(string $input): string {
    return md5($input);
}

function sha256Hash(string $input): string {
    return hash('sha256', $input);
}

function crc32Hash(string $input): string {
    return sprintf('%u', crc32($input));
}

function passwordHash(string $password): string {
    return password_hash($password, PASSWORD_DEFAULT);
}

function verifyPassword(string $password, string $hash): bool {
    return password_verify($password, $hash);
}

$input = "Hello World";
echo md5Hash($input) . "\n";
echo sha256Hash($input) . "\n";
echo crc32Hash($input) . "\n";

$hash = passwordHash("secret123");
echo strlen($hash) . "\n";
echo verifyPassword("secret123", $hash) ? 'true' : 'false' . "\n";
echo verifyPassword("wrongpass", $hash) ? 'true' : 'false' . "\n";
echo "OK\n";
