<?php
// 极度混搭: 编码理论 + 汉明码 + 奇偶校验 + CRC + 游程编码 + LZW压缩
echo "=== c034: Hamming + Parity + CRC + RLE + LZW ===\n\n";

class ErrorCorrection {
    public static function parityCheck(array $bits): int {
        return array_sum($bits) % 2;
    }

    public static function hammingEncode(array $data): array {
        // 4 data bits -> 7 encoded bits (Hamming(7,4))
        if (count($data) !== 4) return [];
        $d1 = $data[0]; $d2 = $data[1]; $d3 = $data[2]; $d4 = $data[3];
        $p1 = ($d1 + $d2 + $d4) % 2;
        $p2 = ($d1 + $d3 + $d4) % 2;
        $p3 = ($d2 + $d3 + $d4) % 2;
        return [$p1, $d1, $p2, $d2, $p3, $d3, $d4];
    }

    public static function hammingDecode(array $encoded): array {
        if (count($encoded) !== 7) return [];
        $p1 = $encoded[0]; $d1 = $encoded[1]; $p2 = $encoded[2]; $d2 = $encoded[3];
        $p3 = $encoded[4]; $d3 = $encoded[5]; $d4 = $encoded[6];

        $s1 = ($p1 + $d1 + $d2 + $d4) % 2;
        $s2 = ($p2 + $d1 + $d3 + $d4) % 2;
        $s3 = ($p3 + $d2 + $d3 + $d4) % 2;
        $errorPos = $s1 * 1 + $s2 * 2 + $s3 * 4;

        if ($errorPos > 0) {
            $encoded[$errorPos - 1] = 1 - $encoded[$errorPos - 1];
        }

        return [$encoded[1], $encoded[3], $encoded[5], $encoded[6]];
    }

    public static function crc16(string $data): int {
        $crc = 0xFFFF;
        $len = strlen($data);
        for ($i = 0; $i < $len; $i++) {
            $crc ^= ord($data[$i]);
            for ($j = 0; $j < 8; $j++) {
                if ($crc & 1) {
                    $crc = ($crc >> 1) ^ 0xA001;
                } else {
                    $crc >>= 1;
                }
            }
        }
        return $crc & 0xFFFF;
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

class RunLengthEncoding {
    public static function encode(string $data): string {
        $result = '';
        $len = strlen($data);
        $i = 0;
        while ($i < $len) {
            $char = $data[$i];
            $count = 1;
            while ($i + $count < $len && $data[$i + $count] === $char) {
                $count++;
            }
            $result .= $char . $count;
            $i += $count;
        }
        return $result;
    }

    public static function decode(string $encoded): string {
        $result = '';
        $len = strlen($encoded);
        $i = 0;
        while ($i < $len) {
            $char = $encoded[$i];
            $countStr = '';
            $i++;
            while ($i < $len && ctype_digit($encoded[$i])) {
                $countStr .= $encoded[$i];
                $i++;
            }
            $count = (int)$countStr;
            $result .= str_repeat($char, $count);
        }
        return $result;
    }
}

class SimpleLZW {
    public static function compress(string $data): array {
        $dict = [];
        for ($i = 0; $i < 256; $i++) {
            $dict[chr($i)] = $i;
        }
        $nextCode = 256;
        $result = [];
        $current = '';

        $len = strlen($data);
        for ($i = 0; $i < $len; $i++) {
            $char = $data[$i];
            $next = $current . $char;
            if (isset($dict[$next])) {
                $current = $next;
            } else {
                $result[] = $dict[$current];
                $dict[$next] = $nextCode++;
                $current = $char;
            }
        }
        if ($current !== '') {
            $result[] = $dict[$current];
        }
        return $result;
    }

    public static function decompress(array $codes): string {
        $dict = [];
        for ($i = 0; $i < 256; $i++) {
            $dict[$i] = chr($i);
        }
        $nextCode = 256;
        $result = '';
        $prev = '';

        foreach ($codes as $code) {
            if (isset($dict[$code])) {
                $entry = $dict[$code];
            } elseif ($code === $nextCode && $prev !== '') {
                $entry = $prev . $prev[0];
            } else {
                return ''; // Error
            }
            $result .= $entry;
            if ($prev !== '') {
                $dict[$nextCode++] = $prev . $entry[0];
            }
            $prev = $entry;
        }
        return $result;
    }
}

// === 测试 ===

echo "--- Parity Check ---\n";
$bits1 = [1, 0, 1, 0, 1, 1, 0, 0];
echo "Data: " . implode("", $bits1) . " parity: " . ErrorCorrection::parityCheck($bits1) . "\n";
$bits2 = [1, 0, 1, 0, 1, 1, 0, 1];
echo "Data: " . implode("", $bits2) . " parity: " . ErrorCorrection::parityCheck($bits2) . "\n";

echo "\n--- Hamming(7,4) ---\n";
$dataBlocks = [[1, 0, 1, 0], [1, 1, 0, 1], [0, 0, 1, 1], [1, 1, 1, 1]];
foreach ($dataBlocks as $data) {
    $encoded = ErrorCorrection::hammingEncode($data);
    echo "Data: " . implode("", $data) . " -> Encoded: " . implode("", $encoded) . "\n";

    // Introduce error at position 3
    $corrupted = $encoded;
    $corrupted[2] = 1 - $corrupted[2];
    $decoded = ErrorCorrection::hammingDecode($corrupted);
    echo "  Corrupted: " . implode("", $corrupted) . " -> Decoded: " . implode("", $decoded) . " ";
    echo ($data === $decoded ? "CORRECTED" : "FAILED") . "\n";
}

echo "\n--- CRC16 ---\n";
$msgs = ["Hello", "World", "Test", "Data integrity check"];
foreach ($msgs as $msg) {
    $crc = ErrorCorrection::crc16($msg);
    printf("  '%s': CRC16=0x%04X\n", $msg, $crc);
}

echo "\n--- Checksum ---\n";
foreach ($msgs as $msg) {
    $cs = ErrorCorrection::checksum($msg);
    echo "  '$msg': checksum=$cs\n";
}

echo "\n--- Run-Length Encoding ---\n";
$testData = [
    "AAABBBCCCAAA",
    "WWWWWWWWWW",
    "ABCDEFGH",
    "AABBCCDD",
    "aaaaaaaaaaaa",
];
foreach ($testData as $data) {
    $encoded = RunLengthEncoding::encode($data);
    $decoded = RunLengthEncoding::decode($encoded);
    $ratio = strlen($encoded) > 0 ? round(strlen($decoded) / strlen($encoded), 2) : 0;
    echo "  '$data' -> '$encoded' -> '$decoded' (ratio: $ratio)\n";
}

echo "\n--- LZW Compression ---\n";
$lzwData = [
    "TOBEORNOTTOBEORTOBEORNOT",
    "ABABABABABABABABABAB",
    "AAAAAAAAAAAAAAA",
    "The quick brown fox",
];
foreach ($lzwData as $data) {
    $compressed = SimpleLZW::compress($data);
    $decompressed = SimpleLZW::decompress($compressed);
    $ratio = count($compressed) > 0 ? round(strlen($data) / count($compressed), 2) : 0;
    $match = $data === $decompressed ? "OK" : "FAIL";
    echo "  '$data' -> codes=" . count($compressed) . " ratio=$ratio $match\n";
}

echo "\n=== c034 Done ===\n";
