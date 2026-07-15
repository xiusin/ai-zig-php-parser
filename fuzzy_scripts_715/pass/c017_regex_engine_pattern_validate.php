<?php
// 极度混搭: 正则表达式引擎 + 模式匹配 + 替换回调 + 分组提取 + 验证链
echo "=== c017: Regex Engine + Pattern Match + Replace Callback + Validate ===\n\n";

class RegexValidator {
    private array $rules = [];
    private array $results = [];

    public function addRule(string $name, string $pattern, string $description): self {
        $this->rules[$name] = ['pattern' => $pattern, 'description' => $description];
        return $this;
    }

    public function validate(string $subject): array {
        $this->results = [];
        foreach ($this->rules as $name => $rule) {
            $matched = preg_match('/' . $rule['pattern'] . '/', $subject) === 1;
            $this->results[$name] = [
                'passed' => $matched,
                'description' => $rule['description'],
            ];
        }
        return $this->results;
    }

    public function validateAll(array $subjects): array {
        $allResults = [];
        foreach ($subjects as $subject) {
            $allResults[$subject] = $this->validate($subject);
        }
        return $allResults;
    }

    public function getPassedRules(): array {
        return array_keys(array_filter($this->results, fn($r) => $r['passed']));
    }

    public function getFailedRules(): array {
        return array_keys(array_filter($this->results, fn($r) => !$r['passed']));
    }
}

class TextProcessor {
    public static function extractEmails(string $text): array {
        preg_match_all('/[\w.+-]+@[\w-]+\.[\w.-]+/', $text, $matches);
        return $matches[0];
    }

    public static function extractUrls(string $text): array {
        preg_match_all('/https?:\/\/[\w\-]+\.[\w\-]+[^\s]*/', $text, $matches);
        return $matches[0];
    }

    public static function extractNumbers(string $text): array {
        preg_match_all('/\d+\.?\d*/', $text, $matches);
        return array_map(fn($n) => (float)$n, $matches[0]);
    }

    public static function extractDates(string $text): array {
        preg_match_all('/(\d{4})-(\d{2})-(\d{2})/', $text, $matches, PREG_SET_ORDER);
        $dates = [];
        foreach ($matches as $m) {
            $dates[] = ['year' => $m[1], 'month' => $m[2], 'day' => $m[3]];
        }
        return $dates;
    }

    public static function extractKeyValues(string $text): array {
        preg_match_all('/(\w+)=([^\s;]+)/', $text, $matches, PREG_SET_ORDER);
        $pairs = [];
        foreach ($matches as $m) {
            $pairs[$m[1]] = $m[2];
        }
        return $pairs;
    }

    public static function camelToSnake(string $str): string {
        return strtolower(preg_replace('/([A-Z])/', '_$1', $str));
    }

    public static function snakeToCamel(string $str): string {
        return preg_replace_callback('/_([a-z])/', fn($m) => strtoupper($m[1]), $str);
    }

    public static function slugify(string $str): string {
        $str = strtolower($str);
        $str = preg_replace('/[^a-z0-9]+/', '-', $str);
        $str = trim($str, '-');
        return $str;
    }

    public static function highlight(string $text, string $keyword): string {
        return preg_replace_callback(
            '/(' . preg_quote($keyword, '/') . ')/i',
            fn($m) => "[$m[1]]",
            $text
        );
    }

    public static function wordFrequency(string $text): array {
        $words = str_word_count(strtolower($text), 1);
        $freq = [];
        foreach ($words as $word) {
            if (!isset($freq[$word])) $freq[$word] = 0;
            $freq[$word]++;
        }
        arsort($freq);
        return $freq;
    }
}

// === 测试 ===

echo "--- Regex Validation ---\n";
$validator = new RegexValidator();
$validator->addRule('email', '^[\w.+-]+@[\w-]+\.[\w.-]+$', 'Valid email format');
$validator->addRule('min_length', '.{8,}', 'At least 8 characters');
$validator->addRule('has_upper', '[A-Z]', 'Contains uppercase');
$validator->addRule('has_digit', '\d', 'Contains digit');
$validator->addRule('has_special', '[!@#$%^&*]', 'Contains special char');

$testStrings = [
    'user@example.com',
    'TestPass123!',
    'short',
    'NoSpecial1',
    'alllowercase',
];

foreach ($testStrings as $str) {
    $validator->validate($str);
    echo "  '$str': passed=[" . implode(",", $validator->getPassedRules()) . "] failed=[" . implode(",", $validator->getFailedRules()) . "]\n";
}

echo "\n--- Text Extraction ---\n";
$samples = [
    'text' => 'Contact alice@example.com or bob@test.org for info. Visit https://example.com/page?id=42 The date is 2024-01-15 and temperature 23.5 degrees.',
];

echo "Emails: " . implode(", ", TextProcessor::extractEmails($samples['text'])) . "\n";
$urls = TextProcessor::extractUrls($samples['text']);
echo "URLs: " . implode(", ", $urls) . "\n";
$numbers = TextProcessor::extractNumbers($samples['text']);
echo "Numbers: " . implode(", ", array_map(fn($n) => (string)$n, $numbers)) . "\n";
$dates = TextProcessor::extractDates($samples['text']);
foreach ($dates as $d) {
    echo "Date: {$d['year']}-{$d['month']}-{$d['day']}\n";
}

echo "\n--- Key-Value Extraction ---\n";
$configStr = "name=MyApp;version=1.0;debug=true;port=8080;host=localhost";
$kvs = TextProcessor::extractKeyValues($configStr);
foreach ($kvs as $k => $v) {
    echo "  $k = $v\n";
}

echo "\n--- String Transforms ---\n";
$camel = "myVariableNameInCamelCase";
$snake = TextProcessor::camelToSnake($camel);
$back = TextProcessor::snakeToCamel($snake);
echo "Camel: $camel\n";
echo "Snake: $snake\n";
echo "Back:  $back\n";

$slug = TextProcessor::slugify("Hello World! This is a Test String.");
echo "Slug: $slug\n";

echo "\n--- Highlight ---\n";
$text = "The quick brown fox jumps over the lazy dog. FOX is clever.";
echo TextProcessor::highlight($text, "fox") . "\n";

echo "\n--- Word Frequency ---\n";
$freq = TextProcessor::wordFrequency("the quick brown fox jumps over the lazy dog the fox is quick");
$top = array_slice($freq, 0, 5, true);
foreach ($top as $word => $count) {
    echo "  $word: $count\n";
}

echo "\n=== c017 Done ===\n";
