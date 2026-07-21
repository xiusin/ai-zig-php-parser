<?php
// 位运算与标志位：权限标志、位域、位图、加密哈希
echo "=== f162: Bitwise + Flags + BitMap + Crypto ===\n";

// 位标志系统
class BitFlags {
    public const READ    = 1;       // 0b0001
    public const WRITE   = 2;       // 0b0010
    public const EXECUTE = 4;       // 0b0100
    public const DELETE  = 8;       // 0b1000
    public const ADMIN   = 16;      // 0b10000
    public const ALL     = 31;      // 0b11111

    public static function has(int $flags, int $permission): bool {
        return ($flags & $permission) === $permission;
    }

    public static function add(int $flags, int $permission): int {
        return $flags | $permission;
    }

    public static function remove(int $flags, int $permission): int {
        return $flags & ~$permission;
    }

    public static function toggle(int $flags, int $permission): int {
        return $flags ^ $permission;
    }

    public static function names(int $flags): array {
        $names = [];
        $map = [
            self::READ => 'READ', self::WRITE => 'WRITE',
            self::EXECUTE => 'EXECUTE', self::DELETE => 'DELETE',
            self::ADMIN => 'ADMIN',
        ];
        foreach ($map as $bit => $name) {
            if (self::has($flags, $bit)) $names[] = $name;
        }
        return $names;
    }

    public static function toBinary(int $flags, int $bits = 8): string {
        return str_pad(decbin($flags), $bits, '0', STR_PAD_LEFT);
    }
}

// 位图
class BitMap {
    private string $data;
    private int $size;

    public function __construct(int $size) {
        $this->size = $size;
        $this->data = str_repeat("\0", (int)ceil($size / 8));
    }

    public function set(int $index): void {
        if ($index < 0 || $index >= $this->size) return;
        $byteIndex = intdiv($index, 8);
        $bitIndex = $index % 8;
        $this->data[$byteIndex] = chr(ord($this->data[$byteIndex]) | (1 << $bitIndex));
    }

    public function clear(int $index): void {
        if ($index < 0 || $index >= $this->size) return;
        $byteIndex = intdiv($index, 8);
        $bitIndex = $index % 8;
        $this->data[$byteIndex] = chr(ord($this->data[$byteIndex]) & ~(1 << $bitIndex));
    }

    public function test(int $index): bool {
        if ($index < 0 || $index >= $this->size) return false;
        $byteIndex = intdiv($index, 8);
        $bitIndex = $index % 8;
        return (ord($this->data[$byteIndex]) & (1 << $bitIndex)) !== 0;
    }

    public function count(): int {
        $count = 0;
        for ($i = 0; $i < strlen($this->data); $i++) {
            $byte = ord($this->data[$i]);
            while ($byte) {
                $count += $byte & 1;
                $byte >>= 1;
            }
        }
        return $count;
    }

    public function getSetBits(): array {
        $bits = [];
        for ($i = 0; $i < $this->size; $i++) {
            if ($this->test($i)) $bits[] = $i;
        }
        return $bits;
    }
}

// CRC32 实现
class Crc32 {
    private static ?array $table = null;

    private static function initTable(): array {
        if (self::$table !== null) return self::$table;
        $table = [];
        for ($i = 0; $i < 256; $i++) {
            $crc = $i;
            for ($j = 0; $j < 8; $j++) {
                if ($crc & 1) {
                    $crc = 0xEDB88320 ^ (($crc >> 1) & 0x7FFFFFFF);
                } else {
                    $crc = ($crc >> 1) & 0x7FFFFFFF;
                }
            }
            $table[$i] = $crc;
        }
        self::$table = $table;
        return $table;
    }

    public static function compute(string $data): int {
        $table = self::initTable();
        $crc = 0xFFFFFFFF;
        for ($i = 0; $i < strlen($data); $i++) {
            $crc = $table[($crc ^ ord($data[$i])) & 0xFF] ^ (($crc >> 8) & 0x00FFFFFF);
        }
        return $crc ^ 0xFFFFFFFF;
    }
}

// HMAC 简易实现
class SimpleHmac {
    public static function compute(string $key, string $message, string $algo = 'sha256'): string {
        $blockSize = 64;
        if (strlen($key) > $blockSize) {
            $key = hash($algo, $key, true);
        }
        $key = str_pad($key, $blockSize, "\0");
        $oKeyPad = str_repeat('', $blockSize);
        $iKeyPad = str_repeat('', $blockSize);
        for ($i = 0; $i < $blockSize; $i++) {
            $oKeyPad[$i] = chr(ord($key[$i]) ^ 0x5C);
            $iKeyPad[$i] = chr(ord($key[$i]) ^ 0x36);
        }
        $inner = hash($algo, $iKeyPad . $message, true);
        return hash_hmac($algo, $message, $key);
    }
}

// 测试
echo "--- Bit Flags ---\n";
$perm = BitFlags::READ | BitFlags::WRITE;
echo "  Initial: " . implode(' | ', BitFlags::names($perm)) . " (" . BitFlags::toBinary($perm, 5) . ")\n";
$perm = BitFlags::add($perm, BitFlags::EXECUTE);
echo "  After add EXECUTE: " . implode(' | ', BitFlags::names($perm)) . "\n";
$perm = BitFlags::remove($perm, BitFlags::WRITE);
echo "  After remove WRITE: " . implode(' | ', BitFlags::names($perm)) . "\n";
$perm = BitFlags::toggle($perm, BitFlags::DELETE);
echo "  After toggle DELETE: " . implode(' | ', BitFlags::names($perm)) . "\n";
echo "  Has READ: " . (BitFlags::has($perm, BitFlags::READ) ? 'Y' : 'N') . "\n";
echo "  Has ADMIN: " . (BitFlags::has($perm, BitFlags::ADMIN) ? 'Y' : 'N') . "\n";

echo "\n--- BitMap ---\n";
$bitmap = new BitMap(32);
$primes = [2, 3, 5, 7, 11, 13, 17, 19, 23, 29, 31];
foreach ($primes as $p) $bitmap->set($p);
echo "  Set bits: " . implode(', ', $bitmap->getSetBits()) . "\n";
echo "  Count: " . $bitmap->count() . "\n";
echo "  Test 7: " . ($bitmap->test(7) ? 'set' : 'clear') . "\n";
echo "  Test 8: " . ($bitmap->test(8) ? 'set' : 'clear') . "\n";
$bitmap->clear(7);
echo "  After clear 7: Test 7=" . ($bitmap->test(7) ? 'set' : 'clear') . "\n";
echo "  Count after clear: " . $bitmap->count() . "\n";

echo "\n--- CRC32 ---\n";
$testData = ['Hello', 'World', 'PHP AOT', 'Zig', ''];
foreach ($testData as $data) {
    $crc = Crc32::compute($data);
    $expected = crc32($data);
    echo "  '$data': custom=" . sprintf('0x%08X', $crc) . " builtin=" . sprintf('0x%08X', $expected) .
         " match=" . ($crc === $expected ? 'Y' : 'N') . "\n";
}

echo "\n--- Hash Functions ---\n";
$texts = ['password', 'hello world', 'PHP AOT Compiler', ''];
foreach ($texts as $text) {
    echo "  '$text':\n";
    echo "    md5: " . md5($text) . "\n";
    echo "    sha1: " . sha1($text) . "\n";
    echo "    sha256: " . hash('sha256', $text) . "\n";
}

echo "\n--- HMAC ---\n";
$key = 'secret_key';
$message = 'Important message';
echo "  Message: '$message'\n";
echo "  Key: '$key'\n";
echo "  HMAC-SHA256: " . hash_hmac('sha256', $message, $key) . "\n";
echo "  HMAC-SHA1: " . hash_hmac('sha1', $message, $key) . "\n";

echo "\n--- Base64 Encoding ---\n";
$original = 'Hello, World! This is a test message.';
$encoded = base64_encode($original);
$decoded = base64_decode($encoded);
echo "  Original: $original\n";
echo "  Encoded: $encoded\n";
echo "  Decoded: $decoded\n";
echo "  Match: " . ($original === $decoded ? 'Y' : 'N') . "\n";

echo "\n--- Bit Manipulation ---\n";
$num = 42;
echo "  Number: $num (" . decbin($num) . ")\n";
echo "  Bit count: " . substr_count(decbin($num), '1') . "\n";
echo "  Reversed bits: " . strrev(decbin($num)) . "\n";
echo "  Is power of 2: " . (($num & ($num - 1)) === 0 ? 'Y' : 'N') . "\n";
$num2 = 64;
echo "  $num2 is power of 2: " . (($num2 & ($num2 - 1)) === 0 ? 'Y' : 'N') . "\n";
echo "  Swap odd/even bits of 42: " . ((($num & 0xAAAAAAAA) >> 1) | (($num & 0x55555555) << 1)) . "\n";

echo "=== f162 Done ===\n";
