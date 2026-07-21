<?php
// 极度混搭: 加密+编码+哈希+签名 (AES简化/RC4/Base64/CRC/SHA1简化)
echo "=== f065: Crypto + RC4 + Base64 + CRC32 + SHA1 ===\n";

class RC4 {
    private array $s = [];
    private int $i = 0;
    private int $j = 0;

    public function __construct(string $key) {
        for ($i = 0; $i < 256; $i++) $this->s[$i] = $i;
        $j = 0;
        $keyLen = strlen($key);
        for ($i = 0; $i < 256; $i++) {
            $j = ($j + $this->s[$i] + ord($key[$i % $keyLen])) % 256;
            $this->swap($i, $j);
        }
    }

    private function swap(int $a, int $b): void {
        $tmp = $this->s[$a]; $this->s[$a] = $this->s[$b]; $this->s[$b] = $tmp;
    }

    public function encrypt(string $data): string {
        $result = '';
        $len = strlen($data);
        for ($k = 0; $k < $len; $k++) {
            $this->i = ($this->i + 1) % 256;
            $this->j = ($this->j + $this->s[$this->i]) % 256;
            $this->swap($this->i, $this->j);
            $t = ($this->s[$this->i] + $this->s[$this->j]) % 256;
            $result .= chr(ord($data[$k]) ^ $this->s[$t]);
        }
        return $result;
    }
}

class CRC32 {
    private static array $table = [];
    private static bool $initialized = false;

    private static function init(): void {
        if (self::$initialized) return;
        for ($i = 0; $i < 256; $i++) {
            $crc = $i;
            for ($j = 0; $j < 8; $j++) {
                $crc = ($crc & 1) ? (0xEDB88320 ^ (($crc >> 1) & 0x7FFFFFFF)) : (($crc >> 1) & 0x7FFFFFFF);
            }
            self::$table[$i] = $crc;
        }
        self::$initialized = true;
    }

    public static function hash(string $data): string {
        self::init();
        $crc = 0xFFFFFFFF;
        $len = strlen($data);
        for ($i = 0; $i < $len; $i++) {
            $crc = self::$table[($crc ^ ord($data[$i])) & 0xFF] ^ (($crc >> 8) & 0x00FFFFFF);
        }
        $crc = $crc ^ 0xFFFFFFFF;
        return sprintf('%08x', $crc);
    }
}

class SimpleSHA1 {
    public static function hash(string $data): string {
        $h0 = 0x67452301;
        $h1 = 0xEFCDAB89;
        $h2 = 0x98BADCFE;
        $h3 = 0x10325476;
        $h4 = 0xC3D2E1F0;

        $ml = strlen($data) * 8;
        $data .= chr(0x80);
        while (strlen($data) % 64 !== 56) $data .= chr(0);
        $data .= pack('N', 0) . pack('N', $ml);

        $chunks = str_split($data, 64);
        foreach ($chunks as $chunk) {
            $w = array_values(unpack('N16', $chunk));
            for ($i = 16; $i < 80; $i++) {
                $v = $w[$i-3] ^ $w[$i-8] ^ $w[$i-14] ^ $w[$i-16];
                $w[$i] = (($v << 1) | ($v >> 31)) & 0xFFFFFFFF;
            }
            $a=$h0; $b=$h1; $c=$h2; $d=$h3; $e=$h4;
            for ($i = 0; $i < 80; $i++) {
                if ($i < 20) { $f = ($b & $c) | (~$b & $d); $k = 0x5A827999; }
                elseif ($i < 40) { $f = $b ^ $c ^ $d; $k = 0x6ED9EBA1; }
                elseif ($i < 60) { $f = ($b & $c) | ($b & $d) | ($c & $d); $k = 0x8F1BBCDC; }
                else { $f = $b ^ $c ^ $d; $k = 0xCA62C1D6; }
                $temp = ((($a << 5) | ($a >> 27)) & 0xFFFFFFFF) + $f + $e + $k + $w[$i];
                $e = $d; $d = $c; $c = (($b << 30) | ($b >> 2)) & 0xFFFFFFFF; $b = $a; $a = $temp & 0xFFFFFFFF;
            }
            $h0 = ($h0 + $a) & 0xFFFFFFFF;
            $h1 = ($h1 + $b) & 0xFFFFFFFF;
            $h2 = ($h2 + $c) & 0xFFFFFFFF;
            $h3 = ($h3 + $d) & 0xFFFFFFFF;
            $h4 = ($h4 + $e) & 0xFFFFFFFF;
        }
        return sprintf('%08x%08x%08x%08x%08x', $h0, $h1, $h2, $h3, $h4);
    }
}

class Base64 {
    private const CHARS = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/';

    public static function encode(string $data): string {
        $result = '';
        $len = strlen($data);
        for ($i = 0; $i < $len; $i += 3) {
            $b1 = ord($data[$i]);
            $b2 = $i + 1 < $len ? ord($data[$i+1]) : 0;
            $b3 = $i + 2 < $len ? ord($data[$i+2]) : 0;
            $result .= self::CHARS[$b1 >> 2];
            $result .= self::CHARS[(($b1 & 0x03) << 4) | ($b2 >> 4)];
            $result .= ($i + 1 < $len) ? self::CHARS[(($b2 & 0x0F) << 2) | ($b3 >> 6)] : '=';
            $result .= ($i + 2 < $len) ? self::CHARS[$b3 & 0x3F] : '=';
        }
        return $result;
    }

    public static function decode(string $data): string {
        $result = '';
        $data = rtrim($data, '=');
        $len = strlen($data);
        $buffer = 0; $bits = 0;
        for ($i = 0; $i < $len; $i++) {
            $char = $data[$i];
            $val = strpos(self::CHARS, $char);
            if ($val === false) continue;
            $buffer = ($buffer << 6) | $val;
            $bits += 6;
            if ($bits >= 8) {
                $bits -= 8;
                $result .= chr(($buffer >> $bits) & 0xFF);
            }
        }
        return $result;
    }
}

// 测试
echo "--- RC4 ---\n";
$rc4 = new RC4('SecretKey');
$plaintext = 'Hello World!';
$encrypted = $rc4->encrypt($plaintext);
$rc4_2 = new RC4('SecretKey');
$decrypted = $rc4_2->encrypt($encrypted);
echo "Plaintext: $plaintext\n";
echo "Encrypted (hex): " . bin2hex($encrypted) . "\n";
echo "Decrypted: $decrypted\n";
echo "Match: " . var_export($plaintext === $decrypted, true) . "\n";

echo "\n--- CRC32 ---\n";
$tests = ['Hello', 'World', 'PHP', 'AOT Compiler', ''];
foreach ($tests as $t) {
    $my = CRC32::hash($t);
    $php = hash('crc32b', $t);
    echo "  CRC32('$t') = $my (PHP: $php) match=" . var_export($my === $php, true) . "\n";
}

echo "\n--- SHA1 ---\n";
foreach (['abc', 'Hello World', 'test string'] as $t) {
    $my = SimpleSHA1::hash($t);
    $php = sha1($t);
    echo "  SHA1('$t') = $my (PHP: $php) match=" . var_export($my === $php, true) . "\n";
}

echo "\n--- Base64 ---\n";
foreach (['Hello', 'Hello World!', 'PHP AOT', ''] as $t) {
    $my = Base64::encode($t);
    $php = base64_encode($t);
    $dec = Base64::decode($my);
    echo "  B64('$t') = $my (PHP: $php) match=" . var_export($my === $php, true) . " decode_match=" . var_export($dec === $t, true) . "\n";
}

echo "\n--- Combined Pipeline ---\n";
$msg = 'Important message';
$key = 'secret';
$signed = SimpleSHA1::hash($msg . $key);
$encoded = Base64::encode($msg) . '.' . $signed;
echo "Message: $msg\n";
echo "Signature: $signed\n";
echo "Token: $encoded\n";

echo "=== f065 Done ===\n";
