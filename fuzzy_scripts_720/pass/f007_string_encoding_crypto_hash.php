<?php
// 极度混搭: 字符串操作 + 编码转换模拟 + 哈希算法 + 简单加密 + 格式化
echo "=== f007: String Ops + Hash + Crypto + Format ===\n";

class StringUtils {
    public static function reverse(string $str): string {
        $len = strlen($str);
        $result = '';
        for ($i = $len - 1; $i >= 0; $i--) {
            $result .= $str[$i];
        }
        return $result;
    }

    public static function camelCase(string $str): string {
        $parts = preg_split('/[_\-\s]+/', $str);
        $result = strtolower($parts[0]);
        for ($i = 1; $i < count($parts); $i++) {
            $result .= ucfirst(strtolower($parts[$i]));
        }
        return $result;
    }

    public static function snakeCase(string $str): string {
        $result = preg_replace('/([A-Z])/', '_$1', $str);
        return strtolower(ltrim($result, '_'));
    }

    public static function kebabCase(string $str): string {
        return str_replace('_', '-', self::snakeCase($str));
    }

    public static function truncate(string $str, int $len, string $suffix = '...'): string {
        if (strlen($str) <= $len) return $str;
        return substr($str, 0, $len - strlen($suffix)) . $suffix;
    }

    public static function pad(string $str, int $len, string $char = ' ', int $type = STR_PAD_RIGHT): string {
        return str_pad($str, $len, $char, $type);
    }

    public static function wordCount(string $str): array {
        $words = preg_split('/\s+/', trim($str));
        $words = array_filter($words, fn($w) => strlen($w) > 0);
        $counts = [];
        foreach ($words as $word) {
            $word = strtolower(trim($word, '.,!?;:"\''));
            if (strlen($word) > 0) {
                $counts[$word] = ($counts[$word] ?? 0) + 1;
            }
        }
        arsort($counts);
        return $counts;
    }

    public static function levenshtein2(string $s1, string $s2): int {
        $len1 = strlen($s1);
        $len2 = strlen($s2);
        if ($len1 === 0) return $len2;
        if ($len2 === 0) return $len1;

        $prev = range(0, $len2);
        for ($i = 1; $i <= $len1; $i++) {
            $curr = [$i];
            for ($j = 1; $j <= $len2; $j++) {
                $cost = $s1[$i-1] === $s2[$j-1] ? 0 : 1;
                $curr[$j] = min($prev[$j] + 1, $curr[$j-1] + 1, $prev[$j-1] + $cost);
            }
            $prev = $curr;
        }
        return $prev[$len2];
    }
}

class SimpleHash {
    public static function djb2(string $str): int {
        $hash = 5381;
        $len = strlen($str);
        for ($i = 0; $i < $len; $i++) {
            $hash = (($hash << 5) + $hash + ord($str[$i])) & 0xFFFFFFFF;
        }
        return $hash;
    }

    public static function fnv1a(string $str): int {
        $hash = 2166136261;
        $len = strlen($str);
        for ($i = 0; $i < $len; $i++) {
            $hash ^= ord($str[$i]);
            $hash = ($hash * 16777619) & 0xFFFFFFFF;
        }
        return $hash;
    }

    public static function xorHash(string $str): int {
        $hash = 0;
        $len = strlen($str);
        for ($i = 0; $i < $len; $i++) {
            $hash ^= ord($str[$i]) << ($i % 8);
        }
        return $hash & 0xFFFFFFFF;
    }
}

class SimpleCipher {
    public static function caesar(string $text, int $shift): string {
        $result = '';
        $len = strlen($text);
        $shift = $shift % 26;
        for ($i = 0; $i < $len; $i++) {
            $c = ord($text[$i]);
            if ($c >= 65 && $c <= 90) {
                $result .= chr((($c - 65 + $shift) % 26 + 26) % 26 + 65);
            } elseif ($c >= 97 && $c <= 122) {
                $result .= chr((($c - 97 + $shift) % 26 + 26) % 26 + 97);
            } else {
                $result .= $text[$i];
            }
        }
        return $result;
    }

    public static function xor(string $text, string $key): string {
        $result = '';
        $tlen = strlen($text);
        $klen = strlen($key);
        for ($i = 0; $i < $tlen; $i++) {
            $result .= chr(ord($text[$i]) ^ ord($key[$i % $klen]));
        }
        return $result;
    }

    public static function base64Encode2(string $text): string {
        return base64_encode($text);
    }
}

// === 测试 ===
echo "--- String Utils ---\n";
echo "reverse('hello'): " . StringUtils::reverse('hello') . "\n";
echo "camelCase('hello_world foo-bar'): " . StringUtils::camelCase('hello_world foo-bar') . "\n";
echo "snakeCase('HelloWorldFooBar'): " . StringUtils::snakeCase('HelloWorldFooBar') . "\n";
echo "kebabCase('HelloWorldFooBar'): " . StringUtils::kebabCase('HelloWorldFooBar') . "\n";
echo "truncate('Hello World', 8): " . StringUtils::truncate('Hello World', 8) . "\n";
echo "pad('42', 5, '0', STR_PAD_LEFT): " . StringUtils::pad('42', 5, '0', STR_PAD_LEFT) . "\n";
echo "pad('42', 5, '0', STR_PAD_BOTH): " . StringUtils::pad('42', 5, '0', STR_PAD_BOTH) . "\n";

$wordCounts = StringUtils::wordCount("the quick brown fox jumps over the lazy dog the end");
echo "wordCount top 3: ";
$top3 = array_slice($wordCounts, 0, 3, true);
echo json_encode($top3) . "\n";

echo "levenshtein('kitten','sitting'): " . StringUtils::levenshtein2('kitten', 'sitting') . "\n";
echo "levenshtein('hello','hallo'): " . StringUtils::levenshtein2('hello', 'hallo') . "\n";

echo "\n--- Hash ---\n";
$text = "Hello, World!";
echo "djb2('$text'): " . SimpleHash::djb2($text) . "\n";
echo "fnv1a('$text'): " . SimpleHash::fnv1a($text) . "\n";
echo "xorHash('$text'): " . SimpleHash::xorHash($text) . "\n";

echo "\n--- Cipher ---\n";
$encrypted = SimpleCipher::caesar("Hello World", 3);
echo "caesar('Hello World', 3): $encrypted\n";
$decrypted = SimpleCipher::caesar($encrypted, -3);
echo "caesar decrypt: $decrypted\n";

$xorEnc = SimpleCipher::xor("Secret Message", "key");
echo "xor encrypted (hex): " . bin2hex($xorEnc) . "\n";
$xorDec = SimpleCipher::xor($xorEnc, "key");
echo "xor decrypted: $xorDec\n";

$encoded = SimpleCipher::base64Encode2("Hello, World!");
echo "base64: $encoded\n";

echo "=== f007 Done ===\n";
