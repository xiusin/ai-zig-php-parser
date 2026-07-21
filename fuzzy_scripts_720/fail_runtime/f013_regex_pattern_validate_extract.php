<?php
// 极度混搭: 正则引擎 + 模式匹配 + 替换 + 验证 + 提取
echo "=== f013: Regex Engine + Pattern Match + Validate ===\n";

class RegexTester {
    private array $results = [];

    public function test(string $name, string $pattern, string $subject, int $flags = 0): self {
        $matches = [];
        $match = preg_match($pattern, $subject, $matches, $flags);
        $this->results[] = [
            'name' => $name,
            'pattern' => $pattern,
            'subject' => $subject,
            'matched' => $match === 1,
            'matches' => $matches,
        ];
        return $this;
    }

    public function testAll(string $name, string $pattern, string $subject): self {
        $matches = [];
        $count = preg_match_all($pattern, $subject, $matches);
        $this->results[] = [
            'name' => $name,
            'pattern' => $pattern,
            'subject' => $subject,
            'matched' => $count > 0,
            'count' => $count,
            'matches' => $matches[0] ?? [],
        ];
        return $this;
    }

    public function report(): void {
        foreach ($this->results as $r) {
            $status = $r['matched'] ? 'MATCH' : 'NO MATCH';
            echo "  {$r['name']}: $status";
            if (isset($r['count'])) echo " ({$r['count']} matches)";
            if (!empty($r['matches'])) {
                echo " → " . json_encode(array_slice($r['matches'], 0, 3));
            }
            echo "\n";
        }
    }
}

class Validator {
    public static function email(string $email): bool {
        return (bool)preg_match('/^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$/', $email);
    }

    public static function phone(string $phone): bool {
        return (bool)preg_match('/^\+?[\d\s\-\(\)]{10,15}$/', $phone);
    }

    public static function url(string $url): bool {
        return (bool)preg_match('#^https?://[a-zA-Z0-9\-\._~:/\?#\[\]@!$&\'\(\)\*\+,;=]+$#', $url);
    }

    public static function ipv4(string $ip): bool {
        return (bool)preg_match('/^(\d{1,3})\.(\d{1,3})\.(\d{1,3})\.(\d{1,3})$/', $ip, $m)
            && $m[1] <= 255 && $m[2] <= 255 && $m[3] <= 255 && $m[4] <= 255;
    }

    public static function date(string $date): bool {
        return (bool)preg_match('/^(\d{4})-(\d{2})-(\d{2})$/', $date, $m)
            && $m[2] >= 1 && $m[2] <= 12 && $m[3] >= 1 && $m[3] <= 31;
    }

    public static function hexColor(string $color): bool {
        return (bool)preg_match('/^#([0-9a-fA-F]{3}|[0-9a-fA-F]{6})$/', $color);
    }

    public static function username(string $name): bool {
        return (bool)preg_match('/^[a-zA-Z][a-zA-Z0-9_]{3,19}$/', $name);
    }

    public static function password(string $pwd): array {
        $checks = [
            'length' => strlen($pwd) >= 8,
            'upper' => (bool)preg_match('/[A-Z]/', $pwd),
            'lower' => (bool)preg_match('/[a-z]/', $pwd),
            'digit' => (bool)preg_match('/\d/', $pwd),
            'special' => (bool)preg_match('/[^a-zA-Z0-9]/', $pwd),
        ];
        $checks['valid'] = !in_array(false, $checks);
        return $checks;
    }
}

class TextProcessor {
    public static function extractEmails(string $text): array {
        preg_match_all('/[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}/', $text, $matches);
        return $matches[0];
    }

    public static function extractUrls(string $text): array {
        preg_match_all('#https?://[a-zA-Z0-9\-\._~:/\?#\[\]@!$&\'\(\)\*\+,;=]+#', $text, $matches);
        return $matches[0];
    }

    public static function extractNumbers(string $text): array {
        preg_match_all('/-?\d+\.?\d*/', $text, $matches);
        return array_map('floatval', $matches[0]);
    }

    public static function camelToWords(string $camel): string {
        return preg_replace('/([a-z])([A-Z])/', '$1 $2', $camel);
    }

    public static function slugify(string $text): string {
        $text = strtolower($text);
        $text = preg_replace('/[^a-z0-9]+/', '-', $text);
        return trim($text, '-');
    }

    public static function maskEmail(string $email): string {
        return preg_replace('/(?<=.).(?=.*@)/', '*', $email);
    }

    public static function highlight(string $text, string $keyword): string {
        return preg_replace('/(' . preg_quote($keyword, '/') . ')/i', '[$1]', $text);
    }
}

// === 测试 ===
echo "--- Regex Tester ---\n";
$tester = new RegexTester();
$tester
    ->test('simple match', '/hello/', 'hello world')
    ->test('anchored', '/^hello/', 'hello world')
    ->test('end anchor', '/world$/', 'hello world')
    ->test('digits', '/\d{3}/', 'abc123def')
    ->test('capture', '/(\w+)@(\w+)/', 'user@domain')
    ->testAll('all digits', '/\d+/', 'a1b22c333')
    ->testAll('words', '/\w+/', 'hello world foo')
    ->report();

echo "\n--- Validator ---\n";
$emails = ['alice@example.com', 'bob@invalid', 'charlie@test.co.uk', '@nodomain.com'];
foreach ($emails as $e) {
    echo "  email '$e': " . var_export(Validator::email($e), true) . "\n";
}

$phones = ['+1-234-567-8900', '12345', 'abc', '(555) 123-4567'];
foreach ($phones as $p) {
    echo "  phone '$p': " . var_export(Validator::phone($p), true) . "\n";
}

$ips = ['192.168.1.1', '256.0.0.1', '10.0.0.255', '1.2.3'];
foreach ($ips as $ip) {
    echo "  ipv4 '$ip': " . var_export(Validator::ipv4($ip), true) . "\n";
}

$colors = ['#fff', '#aabbcc', '#1234567', '#GGG', '#1a2B3c'];
foreach ($colors as $c) {
    echo "  hex '$c': " . var_export(Validator::hexColor($c), true) . "\n";
}

$pwd = 'P@ssw0rd!';
$checks = Validator::password($pwd);
echo "  password '$pwd': " . json_encode($checks) . "\n";

echo "\n--- Text Processor ---\n";
$text = "Contact alice@example.com or bob@test.org. Visit https://example.com. Call 555-1234. Temp 23.5 degrees. -42 is cold.";
echo "Emails: " . implode(', ', TextProcessor::extractEmails($text)) . "\n";
echo "URLs: " . implode(', ', TextProcessor::extractUrls($text)) . "\n";
echo "Numbers: " . implode(', ', array_map(fn($n) => (string)$n, TextProcessor::extractNumbers($text))) . "\n";

echo "camelToWords('helloWorldFoo'): " . TextProcessor::camelToWords('helloWorldFoo') . "\n";
echo "slugify('Hello World! Foo-Bar'): " . TextProcessor::slugify('Hello World! Foo-Bar') . "\n";
echo "maskEmail('alice@example.com'): " . TextProcessor::maskEmail('alice@example.com') . "\n";
echo "highlight('Hello World', 'world'): " . TextProcessor::highlight('Hello World', 'world') . "\n";

echo "=== f013 Done ===\n";
