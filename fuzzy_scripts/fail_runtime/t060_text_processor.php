<?php
// 文本处理器：CSV 解析、词频统计、文本转换

class TextProcessor {
    private string $text;

    public function __construct(string $text) {
        $this->text = $text;
    }

    public function wordCount(): int {
        return str_word_count($this->text);
    }

    public function wordFrequency(): array {
        $words = str_word_count(strtolower($this->text), 1);
        $freq = [];
        foreach ($words as $word) {
            if (!isset($freq[$word])) $freq[$word] = 0;
            $freq[$word]++;
        }
        arsort($freq);
        return $freq;
    }

    public function toSlug(): string {
        $slug = strtolower($this->text);
        $slug = preg_replace('/[^a-z0-9]+/', '-', $slug);
        $slug = trim($slug, '-');
        return $slug;
    }

    public function excerpt(int $length = 50): string {
        if (strlen($this->text) <= $length) return $this->text;
        return substr($this->text, 0, $length) . '...';
    }

    public function toCsv(): array {
        return array_map(function($line) {
            return str_getcsv($line);
        }, explode("\n", $this->text));
    }

    public static function fromCsv(string $csv): array {
        $lines = explode("\n", trim($csv));
        $headers = str_getcsv($lines[0]);
        $rows = [];
        for ($i = 1; $i < count($lines); $i++) {
            $values = str_getcsv($lines[$i]);
            $row = [];
            for ($j = 0; $j < count($headers); $j++) {
                $row[$headers[$j]] = $values[$j] ?? '';
            }
            $rows[] = $row;
        }
        return $rows;
    }
}

// 测试词频统计
$processor = new TextProcessor("The quick brown fox runs fast. The lazy dog sleeps. The fox is quick.");
$freq = $processor->wordFrequency();
$parts = [];
foreach ($freq as $word => $count) {
    $parts[] = "$word:$count";
}
echo "word_freq: " . implode(' ', $parts) . "\n";

// 测试字数统计
echo "word_count: " . $processor->wordCount() . "\n";

// 测试 slug
echo "slug: " . (new TextProcessor("Hello World! This is a Test."))->toSlug() . "\n";

// 测试摘要
echo "excerpt: " . (new TextProcessor("This is a very long text that needs to be truncated."))->excerpt(20) . "\n";

// 测试 CSV 解析
$csvText = "name,age,city\nAlice,30,NYC\nBob,25,LA\nCharlie,35,SF";
$rows = TextProcessor::fromCsv($csvText);
echo "csv_rows: " . count($rows) . "\n";
echo "csv_row1: " . $rows[0]['name'] . "," . $rows[0]['age'] . "," . $rows[0]['city'] . "\n";
echo "csv_row2: " . $rows[1]['name'] . "," . $rows[1]['age'] . "," . $rows[1]['city'] . "\n";

// 测试 str_getcsv
$parsed = str_getcsv('a,b,c', ',', '"', '\\');
echo "str_getcsv: " . implode('|', $parsed) . "\n";

// 测试文本转换
$text = "Hello World";
echo "upper: " . strtoupper($text) . "\n";
echo "lower: " . strtolower($text) . "\n";
echo "ucfirst: " . ucfirst("hello") . "\n";
echo "ucwords: " . ucwords("hello world foo") . "\n";

// 测试 trim 系列
echo "trim: [" . trim("  hello  ") . "]\n";
echo "ltrim: [" . ltrim("  hello") . "]\n";
echo "rtrim: [" . rtrim("hello  ") . "]\n";

// 测试 strrev
echo "strrev: " . strrev("Hello") . "\n";
