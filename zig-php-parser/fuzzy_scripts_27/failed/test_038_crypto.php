<?php
// Test 038: Cryptography, hashing, password functions
class CryptoLab {
    public function process(): string {
        $out = "";

        $password = 'secret_password_123';

        $out .= "=== Hashing ===\n";
        $out .= "md5('$password'): " . md5($password) . "\n";
        $out .= "sha1('$password'): " . sha1($password) . "\n";
        $out .= "sha256('$password'): " . hash('sha256', $password) . "\n";
        $out .= "sha512('$password'): " . hash('sha512', $password) . "\n";
        $out .= "hash('ripemd128', '$password'): " . hash('ripemd128', $password) . "\n";

        $out .= "\n=== Hash algorithms ===\n";
        $algos = hash_algos();
        $out .= "Available algos count: " . count($algos) . "\n";
        $out .= "First 5 algos: " . implode(', ', array_slice($algos, 0, 5)) . "\n";

        $out .= "\n=== Hash file ===\n";
        $testFile = sys_get_temp_dir() . '/test_hash.txt';
        file_put_contents($testFile, 'test content for hashing');
        $out .= "hash_file('sha256', file): " . hash_file('sha256', $testFile) . "\n";
        unlink($testFile);

        $out .= "\n=== HMAC ===\n";
        $out .= "hash_hmac('sha256', '$password', 'secret_key'): " . hash_hmac('sha256', $password, 'secret_key') . "\n";

        $out .= "\n=== Hash compare ===\n";
        $hash1 = md5($password);
        $hash2 = md5($password);
        $hash3 = md5('different');
        $out .= "hash_equals(\$hash1, \$hash2): " . (hash_equals($hash1, $hash2) ? 'true' : 'false') . "\n";
        $out .= "hash_equals(\$hash1, \$hash3): " . (hash_equals($hash1, $hash3) ? 'true' : 'false') . "\n";

        return $out;
    }

    public function passwordHash(): string {
        $out = "";
        $password = 'test_password_456';

        $out .= "=== Password hashing ===\n";

        if (function_exists('password_hash')) {
            $hash = password_hash($password, PASSWORD_DEFAULT);
            $out .= "password_hash (DEFAULT): " . substr($hash, 0, 30) . "...\n";

            $hash2 = password_hash($password, PASSWORD_BCRYPT);
            $out .= "password_hash (BCRYPT): " . substr($hash2, 0, 30) . "...\n";

            $out .= "password_verify('$password', \$hash): " . (password_verify($password, $hash) ? 'true' : 'false') . "\n";
            $out .= "password_verify('wrong', \$hash): " . (password_verify('wrong', $hash) ? 'true' : 'false') . "\n";

            $out .= "password_get_info(\$hash) algo: " . (password_get_info($hash))[0] . "\n";

            $out .= "password_needs_rehash(\$hash, PASSWORD_DEFAULT): " . (password_needs_rehash($hash, PASSWORD_DEFAULT) ? 'true' : 'false') . "\n";
        } else {
            $out .= "password_hash not available\n";
        }

        return $out;
    }
}

echo "=== Crypto Lab ===\n";
$lab = new CryptoLab();
echo $lab->process();

echo "\n";
echo $lab->passwordHash();

echo "\n=== Random bytes ===\n";
$bytes = random_bytes(16);
echo "random_bytes(16) hex: " . bin2hex($bytes) . "\n";
echo "bin2hex(random_bytes(8)): " . bin2hex(random_bytes(8)) . "\n";

echo "\n=== Salt simulation ===\n";
$salt = bin2hex(random_bytes(16));
echo "Generated salt: " . $salt . "\n";
$password = 'test';
$salted = hash('sha256', $password . $salt);
echo "Salted hash: " . $salted . "\n";