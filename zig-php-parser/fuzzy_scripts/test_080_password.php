<?php
// Test 080: Password hashing
if (!function_exists('password_hash')) {
    echo "password_hash not available\n";
    exit(0);
}

echo "=== Password hash ===\n";
$password = 'test_password_123';
$hash = password_hash($password, PASSWORD_DEFAULT);
echo "Hash: " . substr($hash, 0, 30) . "...\n";

echo "\n=== Verify ===\n";
echo "Correct password: " . (password_verify($password, $hash) ? 'valid' : 'invalid') . "\n";
echo "Wrong password: " . (password_verify('wrong', $hash) ? 'valid' : 'invalid') . "\n";

echo "\n=== Bcrypt ===\n";
$bcrypt = password_hash($password, PASSWORD_BCRYPT, ['cost' => 10]);
echo "Bcrypt: " . substr($bcrypt, 0, 30) . "...\n";

echo "\n=== Password info ===\n";
$info = password_get_info($hash);
echo "Algo: " . $info['algo'] . "\n";
echo "Algo name: " . $info['algoName'] . "\n";
echo "Options: " . json_encode($info['options']) . "\n";

echo "\n=== Needs rehash ===\n";
echo "Needs rehash (same algo): " . (password_needs_rehash($hash, PASSWORD_DEFAULT) ? 'yes' : 'no') . "\n";
$new_algo_hash = password_hash($password, PASSWORD_BCRYPT);
echo "Needs rehash (diff algo): " . (password_needs_rehash($new_algo_hash, PASSWORD_DEFAULT) ? 'yes' : 'no') . "\n";