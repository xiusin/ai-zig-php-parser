<?php
// 极度混搭: 字符串编码 + 位运算 + CRC + Base64 + 数组旋转 + 加密原语
echo "=== c005: String Encoding + BitOps + CRC + Rotation ===\n\n";

class CryptoUtils {
    public static function rot13(string $str): string {
        $result = '';
        $len = strlen($str);
        for ($i = 0; $i < $len; $i++) {
            $c = ord($str[$i]);
            if ($c >= 65 && $c <= 90) {
                $result .= chr((($c - 65 + 13) % 26) + 65);
            } elseif ($c >= 97 && $c <= 122) {
                $result .= chr((($c - 97 + 13) % 26) + 97);
            } else {
                $result .= $str[$i];
            }
        }
        return $result;
    }

    public static function xorEncrypt(string $data, int $key): string {
        $result = '';
        $len = strlen($data);
        for ($i = 0; $i < $len; $i++) {
            $result .= chr(ord($data[$i]) ^ ($key & 0xFF));
            $key = ($key * 1103515245 + 12345) & 0x7FFFFFFF;
        }
        return $result;
    }

    public static function simpleHash(string $data): int {
        $hash = 0;
        $len = strlen($data);
        for ($i = 0; $i < $len; $i++) {
            $hash = (($hash << 5) + $hash + ord($data[$i])) & 0x7FFFFFFF;
        }
        return $hash;
    }

    public static function caesarShift(string $text, int $shift): string {
        $shift = $shift % 26;
        if ($shift < 0) $shift += 26;
        $result = '';
        $len = strlen($text);
        for ($i = 0; $i < $len; $i++) {
            $c = ord($text[$i]);
            if ($c >= 65 && $c <= 90) {
                $result .= chr((($c - 65 + $shift) % 26) + 65);
            } elseif ($c >= 97 && $c <= 122) {
                $result .= chr((($c - 97 + $shift) % 26) + 97);
            } else {
                $result .= $text[$i];
            }
        }
        return $result;
    }

    public static function reverseBits(int $n): int {
        $result = 0;
        for ($i = 0; $i < 32; $i++) {
            $result = ($result << 1) | ($n & 1);
            $n >>= 1;
        }
        return $result;
    }

    public static function toBinary(int $n): string {
        if ($n == 0) return '0';
        $bin = '';
        while ($n > 0) {
            $bin = ($n & 1) . $bin;
            $n >>= 1;
        }
        return $bin;
    }

    public static function fromBinary(string $bin): int {
        $val = 0;
        $len = strlen($bin);
        for ($i = 0; $i < $len; $i++) {
            $val = ($val << 1) | (ord($bin[$i]) - ord('0'));
        }
        return $val;
    }

    public static function checksum(string $data): int {
        $sum = 0;
        $len = strlen($data);
        for ($i = 0; $i < $len; $i++) {
            $sum = ($sum + ord($data[$i])) & 0xFFFF;
        }
        return $sum;
    }
}

// === 测试 ===

// 1. ROT13
$original = "Hello World! PHP is great.";
$encoded = CryptoUtils::rot13($original);
$decoded = CryptoUtils::rot13($encoded);
echo "ROT13 original: $original\n";
echo "ROT13 encoded: $encoded\n";
echo "ROT13 decoded: $decoded\n";
echo "ROT13 roundtrip: " . ($original === $decoded ? "OK" : "FAIL") . "\n";

// 2. Caesar shift
$plain = "AttackAtDawn";
for ($shift = 1; $shift <= 5; $shift++) {
    $enc = CryptoUtils::caesarShift($plain, $shift);
    $dec = CryptoUtils::caesarShift($enc, -$shift);
    echo "Caesar($shift): $enc -> $dec " . ($plain === $dec ? "OK" : "FAIL") . "\n";
}

// 3. XOR encryption
$data = "SecretMessage";
$key = 12345;
$xored = CryptoUtils::xorEncrypt($data, $key);
$xoredBack = CryptoUtils::xorEncrypt($xored, $key);
echo "XOR roundtrip: " . ($data === $xoredBack ? "OK" : "FAIL") . "\n";

// 4. Simple hash
$hash1 = CryptoUtils::simpleHash("hello");
$hash2 = CryptoUtils::simpleHash("world");
$hash3 = CryptoUtils::simpleHash("hello");
echo "Hash(hello)=$hash1 Hash(world)=$hash2 Same=" . ($hash1 === $hash3 ? "YES" : "NO") . "\n";

// 5. Binary conversion
foreach ([5, 255, 1024, 0, 65535] as $num) {
    $bin = CryptoUtils::toBinary($num);
    $back = CryptoUtils::fromBinary($bin);
    echo "$num -> $bin -> $back " . ($num === $back ? "OK" : "FAIL") . "\n";
}

// 6. Bit reversal
$bits = CryptoUtils::reverseBits(1);
echo "reverseBits(1) = $bits\n";
echo "reverseBits(255) = " . CryptoUtils::reverseBits(255) . "\n";

// 7. Checksum
$cs1 = CryptoUtils::checksum("test data");
$cs2 = CryptoUtils::checksum("test datb");
echo "Checksum same: " . ($cs1 === $cs2 ? "YES(no change)" : "NO(changed)") . "\n";

// 8. Combined: encode -> hash -> checksum pipeline
$msg = "The quick brown fox";
$enc = CryptoUtils::caesarShift(CryptoUtils::rot13($msg), 7);
$hash = CryptoUtils::simpleHash($enc);
$cs = CryptoUtils::checksum($enc);
echo "Pipeline: msg='$msg' enc='$enc' hash=$hash checksum=$cs\n";

// 9. Array of strings with hash map
$strings = ["apple", "banana", "cherry", "apple", "banana", "date"];
$hashMap = [];
foreach ($strings as $s) {
    $h = CryptoUtils::simpleHash($s);
    if (!isset($hashMap[$h])) $hashMap[$h] = [];
    $hashMap[$h][] = $s;
}
echo "Hash map collisions:\n";
foreach ($hashMap as $h => $vals) {
    echo "  $h: " . implode(", ", $vals) . "\n";
}

// 10. Hex/binary string operations
$hex = dechex(255);
$bin = decbin(255);
$oct = decoct(255);
echo "255: hex=$hex bin=$bin oct=$oct\n";
echo "hex2bin: " . strlen(hex2bin($hex)) . " bytes\n";

echo "\n=== c005 Done ===\n";
