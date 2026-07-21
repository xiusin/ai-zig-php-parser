<?php
// 数据序列化：JSON 深度操作、CSV 处理、简易 XML 解析
echo "=== f161: JSON + CSV + XML Parsing ===\n";

// JSON 深度操作
class JsonHelper {
    public static function encode(mixed $data, int $options = 0): string {
        return json_encode($data, $options);
    }

    public static function decode(string $json, bool $assoc = true): mixed {
        return json_decode($json, $assoc);
    }

    public static function merge(string $json1, string $json2): string {
        $arr1 = self::decode($json1);
        $arr2 = self::decode($json2);
        return self::encode(self::arrayMergeRecursive($arr1, $arr2));
    }

    private static function arrayMergeRecursive(array $arr1, array $arr2): array {
        $result = $arr1;
        foreach ($arr2 as $key => $value) {
            if (is_int($key)) {
                $result[] = $value;
            } elseif (is_array($value) && isset($result[$key]) && is_array($result[$key])) {
                $result[$key] = self::arrayMergeRecursive($result[$key], $value);
            } else {
                $result[$key] = $value;
            }
        }
        return $result;
    }

    public static function extract(string $json, string $path): mixed {
        $data = self::decode($json);
        $parts = explode('.', $path);
        $current = $data;
        foreach ($parts as $part) {
            if (is_array($current) && isset($current[$part])) {
                $current = $current[$part];
            } else {
                return null;
            }
        }
        return $current;
    }

    public static function flatten(string $json, string $prefix = ''): array {
        $data = self::decode($json);
        return self::flattenArray($data, $prefix);
    }

    private static function flattenArray(array $data, string $prefix): array {
        $result = [];
        foreach ($data as $key => $value) {
            $newKey = $prefix === '' ? $key : "$prefix.$key";
            if (is_array($value)) {
                $result = array_merge($result, self::flattenArray($value, $newKey));
            } else {
                $result[$newKey] = $value;
            }
        }
        return $result;
    }

    public static function prettyPrint(string $json): string {
        return json_encode(self::decode($json), JSON_PRETTY_PRINT);
    }
}

// CSV 处理器
class CsvHelper {
    public static function parse(string $csv, string $delimiter = ','): array {
        $lines = explode("\n", trim($csv));
        $headers = str_getcsv(array_shift($lines), $delimiter);
        $rows = [];
        foreach ($lines as $line) {
            if (trim($line) === '') continue;
            $values = str_getcsv($line, $delimiter);
            $rows[] = array_combine($headers, $values);
        }
        return ['headers' => $headers, 'rows' => $rows];
    }

    public static function generate(array $headers, array $rows): string {
        $csv = implode(',', $headers) . "\n";
        foreach ($rows as $row) {
            $values = [];
            foreach ($headers as $header) {
                $val = $row[$header] ?? '';
                if (strpos($val, ',') !== false || strpos($val, '"') !== false || strpos($val, "\n") !== false) {
                    $val = '"' . str_replace('"', '""', $val) . '"';
                }
                $values[] = $val;
            }
            $csv .= implode(',', $values) . "\n";
        }
        return $csv;
    }

    public static function filter(array $data, callable $fn): array {
        return [
            'headers' => $data['headers'],
            'rows' => array_filter($data['rows'], $fn),
        ];
    }

    public static function sort(array $data, string $column, bool $desc = false): array {
        $rows = $data['rows'];
        usort($rows, function($a, $b) use ($column, $desc) {
            $cmp = ($a[$column] ?? '') <=> ($b[$column] ?? '');
            return $desc ? -$cmp : $cmp;
        });
        return ['headers' => $data['headers'], 'rows' => $rows];
    }

    public static function groupBy(array $data, string $column): array {
        $groups = [];
        foreach ($data['rows'] as $row) {
            $key = $row[$column] ?? '';
            $groups[$key][] = $row;
        }
        return $groups;
    }
}

// 简易 XML 解析器
class SimpleXmlParser {
    private string $xml;
    private int $pos = 0;

    public function parse(string $xml): array {
        $this->xml = trim($xml);
        $this->pos = 0;
        return $this->parseElement();
    }

    private function parseElement(): array {
        $this->skipWhitespace();
        if ($this->xml[$this->pos] !== '<') return [];
        $this->pos++; // skip <

        // 检查是否是注释或声明
        if ($this->xml[$this->pos] === '?') {
            $end = strpos($this->xml, '?>', $this->pos);
            $this->pos = $end + 2;
            return $this->parseElement();
        }
        if ($this->xml[$this->pos] === '!') {
            $end = strpos($this->xml, '>', $this->pos);
            $this->pos = $end + 1;
            return $this->parseElement();
        }

        // 读取标签名
        $tagEnd = strpos($this->xml, '>', $this->pos);
        $tagContent = substr($this->xml, $this->pos, $tagEnd - $this->pos);
        $this->pos = $tagEnd + 1;

        // 解析属性和标签名
        $parts = preg_split('/\s+/', $tagContent, 2);
        $tagName = $parts[0];
        $attributes = [];
        if (isset($parts[1])) {
            preg_match_all('/(\w+)="([^"]*)"/', $parts[1], $attrMatches);
            for ($i = 0; $i < count($attrMatches[1]); $i++) {
                $attributes[$attrMatches[1][$i]] = $attrMatches[2][$i];
            }
        }

        // 检查是否自闭合
        if (str_ends_with($tagContent, '/')) {
            return ['tag' => $tagName, 'attributes' => $attributes, 'children' => [], 'text' => ''];
        }

        // 读取子元素和文本
        $children = [];
        $text = '';
        while ($this->pos < strlen($this->xml)) {
            $this->skipWhitespace();
            if ($this->pos >= strlen($this->xml)) break;

            if ($this->xml[$this->pos] === '<') {
                if ($this->xml[$this->pos + 1] === '/') {
                    // 闭合标签
                    $endTag = strpos($this->xml, '>', $this->pos);
                    $this->pos = $endTag + 1;
                    break;
                }
                $children[] = $this->parseElement();
            } else {
                $textEnd = strpos($this->xml, '<', $this->pos);
                if ($textEnd === false) $textEnd = strlen($this->xml);
                $text .= substr($this->xml, $this->pos, $textEnd - $this->pos);
                $this->pos = $textEnd;
            }
        }

        return ['tag' => $tagName, 'attributes' => $attributes, 'children' => $children, 'text' => trim($text)];
    }

    private function skipWhitespace(): void {
        while ($this->pos < strlen($this->xml) && ctype_space($this->xml[$this->pos])) {
            $this->pos++;
        }
    }
}

// 测试
echo "--- JSON Operations ---\n";
$data = [
    'user' => ['name' => 'Alice', 'age' => 30],
    'items' => ['apple', 'banana', 'cherry'],
    'meta' => ['version' => '1.0', 'tags' => ['foo', 'bar']],
];
$json = JsonHelper::encode($data);
echo "  Encoded: $json\n";
echo "  Extract user.name: " . JsonHelper::extract($json, 'user.name') . "\n";
echo "  Extract items.1: " . JsonHelper::extract($json, 'items.1') . "\n";
echo "  Flatten:\n";
foreach (JsonHelper::flatten($json) as $path => $value) {
    echo "    $path = $value\n";
}

$json2 = '{"user":{"email":"alice@example.com"},"meta":{"author":"Admin"}}';
$merged = JsonHelper::merge($json, $json2);
echo "  Merged: $merged\n";

echo "\n--- CSV Operations ---\n";
$csv = "name,age,city,dept
Alice,30,Beijing,Engineering
Bob,25,Shanghai,Sales
Charlie,35,Beijing,Engineering
Diana,28,Shanghai,Marketing";

$parsed = CsvHelper::parse($csv);
echo "  Headers: " . implode(', ', $parsed['headers']) . "\n";
echo "  Rows: " . count($parsed['rows']) . "\n";

$engineers = CsvHelper::filter($parsed, fn($r) => $r['dept'] === 'Engineering');
echo "  Engineers: " . count($engineers['rows']) . "\n";

$sorted = CsvHelper::sort($parsed, 'age', true);
echo "  Oldest first:\n";
foreach ($sorted['rows'] as $row) {
    echo "    {$row['name']}: {$row['age']}\n";
}

$byCity = CsvHelper::groupBy($parsed, 'city');
echo "  By city:\n";
foreach ($byCity as $city => $members) {
    $names = array_map(fn($r) => $r['name'], $members);
    echo "    $city: " . implode(', ', $names) . "\n";
}

echo "\n  Generated CSV:\n";
echo "  " . str_replace("\n", "\n  ", CsvHelper::generate(['name', 'score'], [
    ['name' => 'Team A', 'score' => '95'],
    ['name' => 'Team B', 'score' => '87'],
]));

echo "\n--- XML Parsing ---\n";
$xml = '<?xml version="1.0"?>
<catalog>
    <book id="1" lang="en">
        <title>PHP AOT Guide</title>
        <author>John Doe</author>
        <price>39.99</price>
    </book>
    <book id="2" lang="en">
        <title>Zig Programming</title>
        <author>Jane Smith</author>
        <price>49.99</price>
    </book>
</catalog>';

$parser = new SimpleXmlParser();
$parsed = $parser->parse($xml);
echo "  Root tag: {$parsed['tag']}\n";
echo "  Children: " . count($parsed['children']) . "\n";
foreach ($parsed['children'] as $book) {
    echo "  Book id={$book['attributes']['id']} lang={$book['attributes']['lang']}:\n";
    foreach ($book['children'] as $child) {
        echo "    {$child['tag']}: {$child['text']}\n";
    }
}

echo "=== f161 Done ===\n";
