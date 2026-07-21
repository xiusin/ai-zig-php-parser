<?php
// 极度混搭: 编码理论 + 汉明码 + 奇偶校验 + Reed-Solomon简化 + 纠错
echo "=== f066: Hamming Code + Parity + Error Correction ===\n";

class HammingCode {
    // (7,4) 汉明码: 4位数据 → 7位编码
    // 校验矩阵 H (3x7)
    private const H = [
        [1, 0, 1, 0, 1, 0, 1],
        [0, 1, 1, 0, 0, 1, 1],
        [0, 0, 0, 1, 1, 1, 1],
    ];
    // 生成矩阵 G (4x7)
    private const G = [
        [1, 1, 0, 1, 0, 0, 0],
        [0, 1, 1, 0, 1, 0, 0],
        [1, 1, 1, 0, 0, 1, 0],
        [0, 1, 1, 1, 0, 0, 1],
    ];

    public static function encode4bit(array $data): array {
        // data: 4 bits
        $encoded = array_fill(0, 7, 0);
        for ($i = 0; $i < 4; $i++) {
            for ($j = 0; $j < 7; $j++) {
                $encoded[$j] ^= ($data[$i] & self::G[$i][$j]);
            }
        }
        return $encoded;
    }

    public static function decode7bit(array $received): array {
        // 计算校验子
        $syndrome = [0, 0, 0];
        for ($i = 0; $i < 3; $i++) {
            for ($j = 0; $j < 7; $j++) {
                $syndrome[$i] ^= ($received[$j] & self::H[$i][$j]);
            }
        }
        // 校验子 → 错误位置
        $errorPos = $syndrome[0] * 1 + $syndrome[1] * 2 + $syndrome[2] * 4;
        if ($errorPos > 0) {
            $received[$errorPos - 1] ^= 1; // 纠正
        }
        // 提取数据位 (位置 2, 4, 5, 6)
        return [
            'data' => [$received[2], $received[4], $received[5], $received[6]],
            'error_pos' => $errorPos,
            'corrected' => $errorPos > 0,
        ];
    }

    public static function encodeString(string $data): array {
        $result = [];
        $len = strlen($data);
        for ($i = 0; $i < $len; $i++) {
            $byte = ord($data[$i]);
            // 高4位
            $high = [($byte >> 7) & 1, ($byte >> 6) & 1, ($byte >> 5) & 1, ($byte >> 4) & 1];
            // 低4位
            $low = [($byte >> 3) & 1, ($byte >> 2) & 1, ($byte >> 1) & 1, $byte & 1];
            $result[] = self::encode4bit($high);
            $result[] = self::encode4bit($low);
        }
        return $result;
    }

    public static function decodeBlocks(array $blocks): string {
        $result = '';
        for ($i = 0; $i < count($blocks); $i += 2) {
            $high = self::decode7bit($blocks[$i]);
            $low = self::decode7bit($blocks[$i + 1]);
            $byte = ($high['data'][0] << 7) | ($high['data'][1] << 6) | ($high['data'][2] << 5) | ($high['data'][3] << 4)
                  | ($low['data'][0] << 3) | ($low['data'][1] << 2) | ($low['data'][2] << 1) | $low['data'][3];
            $result .= chr($byte);
        }
        return $result;
    }
}

class ParityCheck {
    public static function evenParity(array $bits): int {
        $count = array_sum($bits);
        return $count % 2 === 0 ? 0 : 1;
    }

    public static function addParityBit(array $bits): array {
        $bits[] = self::evenParity($bits);
        return $bits;
    }

    public static function checkParity(array $bits): bool {
        $data = array_slice($bits, 0, -1);
        $parity = end($bits);
        return self::evenParity($data) === $parity;
    }
}

class Checksum {
    public static function simpleChecksum(string $data): int {
        $sum = 0;
        $len = strlen($data);
        for ($i = 0; $i < $len; $i++) $sum += ord($data[$i]);
        return $sum % 256;
    }

    public static function verifyChecksum(string $data, int $checksum): bool {
        return self::simpleChecksum($data) === $checksum;
    }

    public static function fletcher16(string $data): int {
        $sum1 = 0; $sum2 = 0;
        $len = strlen($data);
        for ($i = 0; $i < $len; $i++) {
            $sum1 = ($sum1 + ord($data[$i])) % 255;
            $sum2 = ($sum2 + $sum1) % 255;
        }
        return ($sum2 << 8) | $sum1;
    }
}

// 测试
echo "--- Hamming (7,4) ---\n";
$testData = [
    [0, 0, 0, 0], [0, 0, 0, 1], [0, 0, 1, 0], [0, 0, 1, 1],
    [0, 1, 0, 0], [1, 0, 1, 0], [1, 1, 1, 1],
];
foreach ($testData as $data) {
    $encoded = HammingCode::encode4bit($data);
    echo "Data [" . implode('', $data) . "] → Encoded [" . implode('', $encoded) . "]\n";
    // 注入错误
    $corrupted = $encoded;
    $corrupted[0] ^= 1;
    $decoded = HammingCode::decode7bit($corrupted);
    echo "  Corrupted [" . implode('', $corrupted) . "] → Decoded [" . implode('', $decoded['data']) . "] error_pos={$decoded['error_pos']} corrected=" . var_export($decoded['corrected'], true) . "\n";
}

echo "\n--- String Encode/Decode ---\n";
$msg = 'Hi';
$blocks = HammingCode::encodeString($msg);
echo "Original: $msg\n";
echo "Blocks: " . count($blocks) . " x 7-bit\n";

// 注入错误
$blocks[0][2] ^= 1;
$blocks[1][5] ^= 1;

$decoded = HammingCode::decodeBlocks($blocks);
echo "Decoded (with 2 errors corrected): $decoded\n";
echo "Match: " . var_export($msg === $decoded, true) . "\n";

echo "\n--- Parity Check ---\n";
$bits = [1, 0, 1, 1, 0, 1, 0, 1];
$withParity = ParityCheck::addParityBit($bits);
echo "Data: [" . implode('', $bits) . "]\n";
echo "With parity: [" . implode('', $withParity) . "]\n";
echo "Parity OK: " . var_export(ParityCheck::checkParity($withParity), true) . "\n";
$corrupted = $withParity;
$corrupted[3] ^= 1;
echo "Corrupted parity OK: " . var_export(ParityCheck::checkParity($corrupted), true) . "\n";

echo "\n--- Checksum ---\n";
$data = 'Hello World';
$ck = Checksum::simpleChecksum($data);
echo "Simple checksum('$data') = $ck\n";
echo "Verify: " . var_export(Checksum::verifyChecksum($data, $ck), true) . "\n";
echo "Verify wrong: " . var_export(Checksum::verifyChecksum($data, $ck + 1), true) . "\n";

$f16 = Checksum::fletcher16($data);
echo "Fletcher16('$data') = $f16 (0x" . dechex($f16) . ")\n";

echo "=== f066 Done ===\n";
