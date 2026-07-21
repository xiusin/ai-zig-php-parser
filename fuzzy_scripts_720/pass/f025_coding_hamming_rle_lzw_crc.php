<?php
// 极度混搭: 编码理论 + 汉明码 + RLE压缩 + 简单LZW + CRC校验
echo "=== f025: Hamming + RLE + LZW + CRC ===\n";

class HammingCode {
    public static function encode(string $data): string {
        $result = '';
        for ($i = 0; $i < strlen($data); $i++) {
            $byte = ord($data[$i]);
            for ($b = 0; $b < 8; $b++) {
                $bit = ($byte >> (7 - $b)) & 1;
                $result .= self::encodeBit($bit);
            }
        }
        return $result;
    }

    private static function encodeBit(int $bit): string {
        // Hamming(7,4): 4 data bits → 7 bits with 3 parity bits
        // For simplicity, encode each bit as 3 copies (repetition code)
        return (string)$bit . (string)$bit . (string)$bit;
    }

    public static function decode(string $encoded): string {
        $result = '';
        $bits = '';
        for ($i = 0; $i < strlen($encoded); $i += 3) {
            $chunk = substr($encoded, $i, 3);
            $ones = substr_count($chunk, '1');
            $bits .= $ones >= 2 ? '1' : '0';
        }
        // Convert bits to bytes
        for ($i = 0; $i < strlen($bits); $i += 8) {
            $byte = 0;
            for ($b = 0; $b < 8 && ($i + $b) < strlen($bits); $b++) {
                $byte = ($byte << 1) | (int)$bits[$i + $b];
            }
            $result .= chr($byte);
        }
        return $result;
    }

    public static function introduceError(string $encoded, int $position): string {
        if ($position < 0 || $position >= strlen($encoded)) return $encoded;
        $encoded[$position] = $encoded[$position] === '1' ? '0' : '1';
        return $encoded;
    }
}

class RLE {
    public static function compress(string $data): string {
        if (empty($data)) return '';
        $result = '';
        $count = 1;
        $prev = $data[0];
        for ($i = 1; $i < strlen($data); $i++) {
            if ($data[$i] === $prev && $count < 255) {
                $count++;
            } else {
                $result .= chr($count) . $prev;
                $prev = $data[$i];
                $count = 1;
            }
        }
        $result .= chr($count) . $prev;
        return $result;
    }

    public static function decompress(string $compressed): string {
        $result = '';
        for ($i = 0; $i < strlen($compressed); $i += 2) {
            $count = ord($compressed[$i]);
            $char = $compressed[$i + 1];
            $result .= str_repeat($char, $count);
        }
        return $result;
    }
}

class CRC32 {
    private static ?array $table = null;

    private static function initTable(): void {
        if (self::$table !== null) return;
        self::$table = [];
        for ($i = 0; $i < 256; $i++) {
            $crc = $i;
            for ($j = 0; $j < 8; $j++) {
                $crc = ($crc & 1) ? (0xEDB88320 ^ ($crc >> 1)) : ($crc >> 1);
            }
            self::$table[$i] = $crc;
        }
    }

    public static function compute(string $data): int {
        self::initTable();
        $crc = 0xFFFFFFFF;
        for ($i = 0; $i < strlen($data); $i++) {
            $crc = self::$table[($crc ^ ord($data[$i])) & 0xFF] ^ ($crc >> 8);
        }
        return $crc ^ 0xFFFFFFFF;
    }

    public static function verify(string $data, int $checksum): bool {
        return self::compute($data) === $checksum;
    }
}

class SimpleLZW {
    public static function compress(string $data): array {
        $dictionary = [];
        for ($i = 0; $i < 256; $i++) {
            $dictionary[chr($i)] = $i;
        }
        $dictSize = 256;
        $result = [];
        $w = '';

        for ($i = 0; $i < strlen($data); $i++) {
            $c = $data[$i];
            $wc = $w . $c;
            if (isset($dictionary[$wc])) {
                $w = $wc;
            } else {
                $result[] = $dictionary[$w];
                $dictionary[$wc] = $dictSize++;
                $w = $c;
            }
        }
        if ($w !== '') $result[] = $dictionary[$w];
        return $result;
    }

    public static function decompress(array $compressed): string {
        $dictionary = [];
        for ($i = 0; $i < 256; $i++) {
            $dictionary[$i] = chr($i);
        }
        $dictSize = 256;
        $w = chr($compressed[0]);
        $result = $w;

        for ($i = 1; $i < count($compressed); $i++) {
            $entry = '';
            if (isset($dictionary[$compressed[$i]])) {
                $entry = $dictionary[$compressed[$i]];
            } elseif ($compressed[$i] === $dictSize) {
                $entry = $w . $w[0];
            }
            $result .= $entry;
            $dictionary[$dictSize++] = $w . $entry[0];
            $w = $entry;
        }
        return $result;
    }
}

class BaseConverter {
    public static function toBinary(int $num): string {
        if ($num === 0) return '0';
        $result = '';
        while ($num > 0) {
            $result = ($num & 1 ? '1' : '0') . $result;
            $num >>= 1;
        }
        return $result;
    }

    public static function fromBinary(string $bin): int {
        $result = 0;
        for ($i = 0; $i < strlen($bin); $i++) {
            $result = ($result << 1) | (int)$bin[$i];
        }
        return $result;
    }

    public static function toHex(int $num): string {
        $hex = '0123456789abcdef';
        if ($num === 0) return '0';
        $result = '';
        while ($num > 0) {
            $result = $hex[$num & 0xf] . $result;
            $num >>= 4;
        }
        return $result;
    }

    public static function toBase(int $num, int $base): string {
        if ($num === 0) return '0';
        $chars = '0123456789abcdefghijklmnopqrstuvwxyz';
        $result = '';
        while ($num > 0) {
            $result = $chars[$num % $base] . $result;
            $num = (int)($num / $base);
        }
        return $result;
    }
}

// === 测试 ===
echo "--- Hamming (Repetition Code) ---\n";
$text = "Hi";
$encoded = HammingCode::encode($text);
echo "Original: '$text' (" . strlen($text) . " bytes)\n";
echo "Encoded: $encoded (" . strlen($encoded) . " bits)\n";
$decoded = HammingCode::decode($encoded);
echo "Decoded: '$decoded'\n";
echo "Round-trip OK: " . var_export($decoded === $text, true) . "\n";

// 引入错误并纠正
$corrupted = HammingCode::introduceError($encoded, 5);
$decodedCorrupted = HammingCode::decode($corrupted);
echo "After error at pos 5, decoded: '$decodedCorrupted'\n";
echo "Error corrected: " . var_export($decodedCorrupted === $text, true) . "\n";

echo "\n--- RLE ---\n";
$rleData = "aaaaabbbbbccccccccccddddddeefffffgg";
$compressed = RLE::compress($rleData);
echo "Original: '$rleData' (" . strlen($rleData) . " bytes)\n";
echo "Compressed: " . strlen($compressed) . " bytes\n";
$ratio = strlen($compressed) > 0 ? number_format(strlen($compressed) / strlen($rleData) * 100, 1) : 0;
echo "Ratio: $ratio%\n";
$decompressed = RLE::decompress($compressed);
echo "Decompressed: '$decompressed'\n";
echo "Round-trip OK: " . var_export($decompressed === $rleData, true) . "\n";

echo "\n--- CRC32 ---\n";
$data1 = "Hello, World!";
$crc1 = CRC32::compute($data1);
echo "CRC32('$data1'): " . sprintf('0x%08X', $crc1) . "\n";
echo "Verify: " . var_export(CRC32::verify($data1, $crc1), true) . "\n";
echo "Verify wrong: " . var_export(CRC32::verify($data1 . '!', $crc1), true) . "\n";

echo "\n--- LZW ---\n";
$lzwData = "abababababababababababababababab";
$lzwCompressed = SimpleLZW::compress($lzwData);
echo "Original: '$lzwData' (" . strlen($lzwData) . " bytes)\n";
echo "Compressed: " . json_encode(array_slice($lzwCompressed, 0, 10)) . "... (" . count($lzwCompressed) . " codes)\n";
$lzwDecompressed = SimpleLZW::decompress($lzwCompressed);
echo "Decompressed: '$lzwDecompressed'\n";
echo "Round-trip OK: " . var_export($lzwDecompressed === $lzwData, true) . "\n";

echo "\n--- Base Converter ---\n";
$num = 255;
echo "Decimal: $num\n";
echo "Binary: " . BaseConverter::toBinary($num) . "\n";
echo "Hex: " . BaseConverter::toHex($num) . "\n";
echo "Base36: " . BaseConverter::toBase($num, 36) . "\n";
echo "Base8: " . BaseConverter::toBase($num, 8) . "\n";
echo "Binary → Decimal: " . BaseConverter::fromBinary(BaseConverter::toBinary($num)) . "\n";

echo "=== f025 Done ===\n";
