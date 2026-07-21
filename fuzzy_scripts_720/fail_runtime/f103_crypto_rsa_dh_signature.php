<?php
// 极度混搭: 密码学 + RSA简化 + DH密钥交换 + 数字签名
echo "=== f103: Crypto RSA + DH + Digital Signature ===\n";

class MathUtils {
    public static function gcd(int $a, int $b): int { return $b === 0 ? $a : self::gcd($b, $a % $b); }

    public static function modInverse(int $a, int $m): int {
        $a = $a % $m;
        for ($x = 1; $x < $m; $x++) {
            if (($a * $x) % $m === 1) return $x;
        }
        return 1;
    }

    public static function modPow(int $base, int $exp, int $mod): int {
        $result = 1; $base = $base % $mod;
        while ($exp > 0) {
            if ($exp % 2 === 1) $result = ($result * $base) % $mod;
            $exp = (int)($exp / 2);
            $base = ($base * $base) % $mod;
        }
        return $result;
    }

    public static function isPrime(int $n): bool {
        if ($n < 2) return false;
        if ($n < 4) return true;
        if ($n % 2 === 0 || $n % 3 === 0) return false;
        for ($i = 5; $i * $i <= $n; $i += 6) {
            if ($n % $i === 0 || $n % ($i + 2) === 0) return false;
        }
        return true;
    }

    public static function randomPrime(int $min, int $max): int {
        $candidates = range($min, $max);
        shuffle($candidates);
        foreach ($candidates as $n) {
            if (self::isPrime($n)) return $n;
        }
        return 2;
    }
}

class RSA {
    public int $n; public int $e; public int $d;

    public function generateKeys(int $p = 0, int $q = 0): void {
        if ($p === 0) $p = MathUtils::randomPrime(100, 500);
        if ($q === 0) $q = MathUtils::randomPrime(100, 500);
        $this->n = $p * $q;
        $phi = ($p - 1) * ($q - 1);
        // 选择 e
        $this->e = 65537;
        if (MathUtils::gcd($this->e, $phi) !== 1) {
            for ($e = 3; $e < $phi; $e += 2) {
                if (MathUtils::gcd($e, $phi) === 1) { $this->e = $e; break; }
            }
        }
        $this->d = MathUtils::modInverse($this->e, $phi);
    }

    public function encrypt(int $message): int {
        return MathUtils::modPow($message, $this->e, $this->n);
    }

    public function decrypt(int $cipher): int {
        return MathUtils::modPow($cipher, $this->d, $this->n);
    }

    public function sign(int $message): int {
        return MathUtils::modPow($message, $this->d, $this->n);
    }

    public function verify(int $message, int $signature): bool {
        return MathUtils::modPow($signature, $this->e, $this->n) === $message;
    }

    public function getPublicKey(): array { return ['n' => $this->n, 'e' => $this->e]; }
    public function getPrivateKey(): array { return ['n' => $this->n, 'd' => $this->d]; }
}

class DiffieHellman {
    public function __construct(public int $p, public int $g) {}

    public function generatePrivateKey(): int { return mt_rand(2, $this->p - 2); }

    public function generatePublicKey(int $privateKey): int {
        return MathUtils::modPow($this->g, $privateKey, $this->p);
    }

    public function computeSharedSecret(int $otherPublicKey, int $myPrivateKey): int {
        return MathUtils::modPow($otherPublicKey, $myPrivateKey, $this->p);
    }
}

class DigitalSignature {
    public static function hashMessage(string $message): int {
        $hash = 0;
        for ($i = 0; $i < strlen($message); $i++) {
            $hash = ($hash * 31 + ord($message[$i])) % 1000000007;
        }
        return abs($hash);
    }

    public static function sign(RSA $rsa, string $message): array {
        $hash = self::hashMessage($message);
        $signature = $rsa->sign($hash);
        return ['message' => $message, 'hash' => $hash, 'signature' => $signature];
    }

    public static function verify(RSA $rsa, array $signed): bool {
        $expectedHash = self::hashMessage($signed['message']);
        if ($expectedHash !== $signed['hash']) return false;
        return $rsa->verify($signed['hash'], $signed['signature']);
    }
}

// 测试
echo "--- RSA Key Generation ---\n";
mt_srand(42);
$rsa = new RSA();
$rsa->generateKeys(61, 53); // 使用小素数便于验证
echo "Public key: " . json_encode($rsa->getPublicKey()) . "\n";
echo "Private key: " . json_encode($rsa->getPrivateKey()) . "\n";

echo "\n--- RSA Encrypt/Decrypt ---\n";
$messages = [42, 100, 200, 1234, 7];
foreach ($messages as $m) {
    $enc = $rsa->encrypt($m);
    $dec = $rsa->decrypt($enc);
    echo "  $m → encrypt=$enc → decrypt=$dec match=" . var_export($m === $dec, true) . "\n";
}

echo "\n--- RSA Sign/Verify ---\n";
foreach ($messages as $m) {
    $sig = $rsa->sign($m);
    $valid = $rsa->verify($m, $sig);
    $tampered = $rsa->verify($m + 1, $sig);
    echo "  msg=$m sig=$sig valid=" . var_export($valid, true) . " tampered=" . var_export($tampered, true) . "\n";
}

echo "\n--- Diffie-Hellman Key Exchange ---\n";
$dh = new DiffieHellman(23, 5); // 小素数便于演示
echo "Public params: p=23, g=5\n";

$alicePriv = $dh->generatePrivateKey();
$alicePub = $dh->generatePublicKey($alicePriv);
echo "Alice: private=$alicePriv public=$alicePub\n";

$bobPriv = $dh->generatePrivateKey();
$bobPub = $dh->generatePublicKey($bobPriv);
echo "Bob: private=$bobPriv public=$bobPub\n";

$aliceSecret = $dh->computeSharedSecret($bobPub, $alicePriv);
$bobSecret = $dh->computeSharedSecret($alicePub, $bobPriv);
echo "Alice computed secret: $aliceSecret\n";
echo "Bob computed secret: $bobSecret\n";
echo "Secrets match: " . var_export($aliceSecret === $bobSecret, true) . "\n";

echo "\n--- Digital Signature ---\n";
$rsa2 = new RSA();
$rsa2->generateKeys(73, 71);
$messages2 = ['Hello World', 'Transfer $1000', 'Meeting at 3pm'];
foreach ($messages2 as $msg) {
    $signed = DigitalSignature::sign($rsa2, $msg);
    $valid = DigitalSignature::verify($rsa2, $signed);
    // 篡改消息
    $tampered = $signed;
    $tampered['message'] = $msg . ' TAMPERED';
    $tamperedValid = DigitalSignature::verify($rsa2, $tampered);
    echo "  '$msg': valid=" . var_export($valid, true) . " tampered_valid=" . var_export($tamperedValid, true) . "\n";
}

echo "\n--- Prime Number Tests ---\n";
$primes = [2, 3, 5, 7, 11, 13, 17, 19, 23, 29, 31, 37, 41, 43, 47];
$nonPrimes = [1, 4, 6, 8, 9, 10, 15, 21, 25, 27, 33, 35, 49];
echo "Primes: ";
foreach ($primes as $p) echo (MathUtils::isPrime($p) ? "✓" : "✗") . "$p ";
echo "\nNon-primes: ";
foreach ($nonPrimes as $p) echo (MathUtils::isPrime($p) ? "✓" : "✗") . "$p ";
echo "\n";

echo "\n--- Modular Arithmetic ---\n";
echo "modPow(2, 10, 1000) = " . MathUtils::modPow(2, 10, 1000) . " (expected 24)\n";
echo "modPow(3, 5, 7) = " . MathUtils::modPow(3, 5, 7) . " (expected 5)\n";
echo "modInverse(3, 11) = " . MathUtils::modInverse(3, 11) . " (expected 4)\n";
echo "gcd(48, 18) = " . MathUtils::gcd(48, 18) . " (expected 6)\n";

echo "=== f103 Done ===\n";
