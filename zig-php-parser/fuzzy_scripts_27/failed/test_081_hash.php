<?php
// Test 081: Hash functions
echo "=== Hash ===\n";
echo "md5('hello'): " . md5('hello') . "\n";
echo "sha1('hello'): " . sha1('hello') . "\n";
echo "sha256('hello'): " . hash('sha256', 'hello') . "\n";
echo "sha512('hello'): " . hash('sha512', 'hello') . "\n";

echo "\n=== Hash algorithms ===\n";
$algos = hash_algos();
echo "Available: " . count($algos) . " algorithms\n";
echo "First 10: " . implode(', ', array_slice($algos, 0, 10)) . "\n";

echo "\n=== Hash file ===\n";
$tmp = sys_get_temp_dir() . '/test_hash.txt';
file_put_contents($tmp, 'content for hashing');
echo "hash_file(sha256): " . hash_file('sha256', $tmp) . "\n";
unlink($tmp);

echo "\n=== HMAC ===\n";
echo "hash_hmac(sha256, 'data', 'key'): " . hash_hmac('sha256', 'data', 'key') . "\n";

echo "\n=== Hash equals ===\n";
$a = hash('sha256', 'test');
$b = hash('sha256', 'test');
$c = hash('sha256', 'other');
echo "hash_equals(a, b): " . (hash_equals($a, $b) ? 'equal' : 'not equal') . "\n";
echo "hash_equals(a, c): " . (hash_equals($a, $c) ? 'equal' : 'not equal') . "\n";