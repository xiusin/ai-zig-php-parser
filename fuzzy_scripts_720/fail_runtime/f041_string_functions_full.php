<?php
// 极度混搭: 内置字符串函数全家桶 + 多字节处理 + 编码转换模拟 + 格式化
echo "=== f041: String Functions Full Suite ===\n";

class StringTools {
    public static function split(string $str, string $delim): array {
        if ($delim === '') return str_split($str);
        return explode($delim, $str);
    }

    public static function join(array $parts, string $glue): string {
        return implode($glue, $parts);
    }

    public static function contains(string $haystack, string $needle): bool {
        return str_contains($haystack, $needle);
    }

    public static function startsWith(string $str, string $prefix): bool {
        return str_starts_with($str, $prefix);
    }

    public static function endsWith(string $str, string $suffix): bool {
        return str_ends_with($str, $suffix);
    }

    public static function indexOf(string $haystack, string $needle): int {
        $pos = strpos($haystack, $needle);
        return $pos === false ? -1 : $pos;
    }

    public static function lastIndexOf(string $haystack, string $needle): int {
        $pos = strrpos($haystack, $needle);
        return $pos === false ? -1 : $pos;
    }

    public static function substring(string $str, int $start, ?int $len = null): string {
        return $len === null ? substr($str, $start) : substr($str, $start, $len);
    }

    public static function repeat(string $str, int $n): string {
        return str_repeat($str, $n);
    }

    public static function replace(string $str, string $search, string $replace): string {
        return str_replace($search, $replace, $str);
    }

    public static function replaceCount(string $str, string $search, string $replace, int $limit): string {
        $count = 0;
        $pos = 0;
        $result = $str;
        while ($count < $limit) {
            $pos = strpos($result, $search, $pos);
            if ($pos === false) break;
            $result = substr($result, 0, $pos) . $replace . substr($result, $pos + strlen($search));
            $pos += strlen($replace);
            $count++;
        }
        return $result;
    }

    public static function pad(string $str, int $len, string $char = ' ', int $type = STR_PAD_RIGHT): string {
        return str_pad($str, $len, $char, $type);
    }

    public static function trim(string $str, string $chars = " \t\n\r\0\x0B"): string {
        return trim($str, $chars);
    }

    public static function toUpper(string $str): string { return strtoupper($str); }
    public static function toLower(string $str): string { return strtolower($str); }
    public static function toTitle(string $str): string { return ucwords($str); }
    public static function capitalize(string $str): string { return ucfirst($str); }

    public static function reverse(string $str): string {
        $result = '';
        for ($i = strlen($str) - 1; $i >= 0; $i--) $result .= $str[$i];
        return $result;
    }

    public static function wordWrap(string $str, int $width = 75, string $break = "\n"): string {
        return wordwrap($str, $width, $break, true);
    }

    public static function sprintf(string $format, mixed ...$args): string {
        return sprintf($format, ...$args);
    }

    public static function chunkSplit(string $str, int $len = 76, string $end = "\n"): string {
        return chunk_split($str, $len, $end);
    }

    public static function countChars(string $str): array {
        $result = [];
        for ($i = 0; $i < strlen($str); $i++) {
            $c = $str[$i];
            $result[$c] = ($result[$c] ?? 0) + 1;
        }
        return $result;
    }

    public static function countWords(string $str): int {
        return str_word_count($str);
    }

    public static function nl2br2(string $str): string {
        return str_replace("\n", "<br>\n", $str);
    }

    public static function stripTags(string $str): string {
        return strip_tags($str);
    }

    public static function htmlspecialchars2(string $str): string {
        return htmlspecialchars($str, ENT_QUOTES, 'UTF-8');
    }
}

// === 测试 ===
$s = "Hello, World! Hello PHP!";
echo "contains('Hello'): " . var_export(StringTools::contains($s, 'Hello'), true) . "\n";
echo "startsWith('Hello'): " . var_export(StringTools::startsWith($s, 'Hello'), true) . "\n";
echo "endsWith('PHP!'): " . var_export(StringTools::endsWith($s, 'PHP!'), true) . "\n";
echo "indexOf('Hello'): " . StringTools::indexOf($s, 'Hello') . "\n";
echo "lastIndexOf('Hello'): " . StringTools::lastIndexOf($s, 'Hello') . "\n";
echo "substring(7,5): '" . StringTools::substring($s, 7, 5) . "'\n";
echo "replace('Hello','Hi'): " . StringTools::replace($s, 'Hello', 'Hi') . "\n";
echo "replaceCount('Hello','Hi',1): " . StringTools::replaceCount($s, 'Hello', 'Hi', 1) . "\n";
echo "pad('42',5,'0',LEFT): " . StringTools::pad('42', 5, '0', STR_PAD_LEFT) . "\n";
echo "toUpper: " . StringTools::toUpper($s) . "\n";
echo "toLower: " . StringTools::toLower($s) . "\n";
echo "toTitle: " . StringTools::toTitle("hello world foo") . "\n";
echo "reverse: " . StringTools::reverse($s) . "\n";
echo "repeat('ab',3): " . StringTools::repeat('ab', 3) . "\n";
echo "chunkSplit('abcdef',2,'-'): " . StringTools::chunkSplit('abcdef', 2, '-') . "\n";
echo "wordWrap: " . StringTools::wordWrap("The quick brown fox jumps over the lazy dog", 15, "|") . "\n";

$counts = StringTools::countChars("aabbbcccc");
echo "countChars: " . json_encode($counts) . "\n";
echo "countWords: " . StringTools::countWords("hello world foo bar") . "\n";

echo "sprintf: " . StringTools::sprintf("Name: %s, Age: %d, Score: %.2f", 'Alice', 30, 95.5) . "\n";
echo "htmlspecialchars: " . StringTools::htmlspecialchars2("<script>alert('xss')</script>") . "\n";
echo "stripTags: " . StringTools::stripTags("<p>Hello <b>World</b></p>") . "\n";

// 多行处理
$multiline = "Line1\nLine2\nLine3";
echo "nl2br: " . StringTools::nl2br2($multiline) . "\n";
echo "split by newline: " . json_encode(StringTools::split($multiline, "\n")) . "\n";

echo "=== f041 Done ===\n";
