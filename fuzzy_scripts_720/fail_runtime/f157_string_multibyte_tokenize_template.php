<?php
// 字符串处理：多字节、编码、解析、转义、分词、模板变量替换
echo "=== f157: String Processing + Multibyte + Tokenize ===\n";

// 多字节字符串处理
class StringProcessor {
    public static function mbStrrev(string $str): string {
        $result = '';
        $len = mb_strlen($str, 'UTF-8');
        for ($i = $len - 1; $i >= 0; $i--) {
            $result .= mb_substr($str, $i, 1, 'UTF-8');
        }
        return $result;
    }

    public static function mbUcwords(string $str): string {
        $result = '';
        $words = mb_split('\s+', $str);
        foreach ($words as $word) {
            if ($result !== '') $result .= ' ';
            $result .= mb_strtoupper(mb_substr($word, 0, 1, 'UTF-8'), 'UTF-8');
            $result .= mb_strtolower(mb_substr($word, 1, null, 'UTF-8'), 'UTF-8');
        }
        return $result;
    }

    public static function truncate(string $str, int $length, string $suffix = '...'): string {
        if (mb_strlen($str, 'UTF-8') <= $length) return $str;
        return mb_substr($str, 0, $length, 'UTF-8') . $suffix;
    }

    public static function camelCase(string $str): string {
        $str = str_replace(['-', '_'], ' ', $str);
        $str = self::mbUcwords($str);
        return str_replace(' ', '', $str);
    }

    public static function snakeCase(string $str): string {
        $str = preg_replace('/([a-z])([A-Z])/', '$1_$2', $str);
        $str = str_replace(['-', ' '], '_', $str);
        return strtolower($str);
    }

    public static function kebabCase(string $str): string {
        return str_replace('_', '-', self::snakeCase($str));
    }

    public static function slugify(string $str): string {
        $str = strtolower($str);
        $str = preg_replace('/[^a-z0-9]+/', '-', $str);
        $str = trim($str, '-');
        return $str;
    }

    public static function levenshteinDistance(string $s1, string $s2): int {
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

    public static function soundex(string $str): string {
        $str = strtoupper($str);
        $str = preg_replace('/[^A-Z]/', '', $str);
        if (strlen($str) === 0) return '';
        $codes = ['B' => '1', 'F' => '1', 'P' => '1', 'V' => '1',
                  'C' => '2', 'G' => '2', 'J' => '2', 'K' => '2', 'Q' => '2', 'S' => '2', 'X' => '2', 'Z' => '2',
                  'D' => '3', 'T' => '3', 'L' => '4', 'M' => '5', 'N' => '5', 'R' => '6'];
        $result = $str[0];
        $prevCode = $codes[$str[0]] ?? '';
        for ($i = 1; $i < strlen($str) && strlen($result) < 4; $i++) {
            $code = $codes[$str[$i]] ?? '';
            if ($code !== '' && $code !== $prevCode) {
                $result .= $code;
            }
            $prevCode = $code;
        }
        return str_pad($result, 4, '0');
    }
}

// 模板变量替换
class StringTemplate {
    private string $template;
    private string $leftDelimiter;
    private string $rightDelimiter;

    public function __construct(string $template, string $left = '{{', string $right = '}}') {
        $this->template = $template;
        $this->leftDelimiter = preg_quote($left, '/');
        $this->rightDelimiter = preg_quote($right, '/');
    }

    public function render(array $data): string {
        $result = $this->template;

        // 条件块 {{if condition}}...{{else}}...{{/if}}
        $result = preg_replace_callback(
            '/' . $this->leftDelimiter . 'if\s+(\w+)' . $this->rightDelimiter . '(.*?)' . $this->leftDelimiter . '\/if' . $this->rightDelimiter . '/s',
            function($m) use ($data) {
                $cond = $m[1];
                $body = $m[2];
                if (strpos($body, '{{else}}') !== false) {
                    [$true, $false] = explode('{{else}}', $body, 2);
                } else {
                    $true = $body;
                    $false = '';
                }
                return !empty($data[$cond]) ? $true : $false;
            },
            $result
        );

        // 循环 {{foreach items}}...{{/foreach}}
        $result = preg_replace_callback(
            '/' . $this->leftDelimiter . 'foreach\s+(\w+)' . $this->rightDelimiter . '(.*?)' . $this->leftDelimiter . '\/foreach' . $this->rightDelimiter . '/s',
            function($m) use ($data) {
                $var = $m[1];
                $body = $m[2];
                $list = $data[$var] ?? [];
                $result = '';
                foreach ($list as $item) {
                    $rendered = $body;
                    if (is_array($item)) {
                        foreach ($item as $k => $v) {
                            $rendered = str_replace('{{' . $k . '}}', (string)$v, $rendered);
                        }
                    } else {
                        $rendered = str_replace('{{item}}', (string)$item, $rendered);
                    }
                    $result .= $rendered;
                }
                return $result;
            },
            $result
        );

        // 简单变量 {{var}}
        $result = preg_replace_callback(
            '/' . $this->leftDelimiter . '(\w+)' . $this->rightDelimiter . '/',
            fn($m) => (string)($data[$m[1]] ?? ''),
            $result
        );

        return $result;
    }
}

// 测试
echo "--- Multibyte String Operations ---\n";
echo "  mbStrrev('Hello'): " . StringProcessor::mbStrrev('Hello') . "\n";
echo "  mbUcwords('hello world foo'): " . StringProcessor::mbUcwords('hello world foo') . "\n";
echo "  truncate('Hello World', 5): " . StringProcessor::truncate('Hello World', 5) . "\n";

echo "\n--- Case Conversion ---\n";
$strings = ['hello_world', 'HelloWorld', 'hello-world', 'HELLO WORLD'];
foreach ($strings as $s) {
    echo "  '$s':\n";
    echo "    camel: " . StringProcessor::camelCase($s) . "\n";
    echo "    snake: " . StringProcessor::snakeCase($s) . "\n";
    echo "    kebab: " . StringProcessor::kebabCase($s) . "\n";
    echo "    slug: " . StringProcessor::slugify($s) . "\n";
}

echo "\n--- Levenshtein Distance ---\n";
$pairs = [
    ['kitten', 'sitting'],
    ['saturday', 'sunday'],
    ['hello', 'hallo'],
    ['world', 'word'],
    ['', 'abc'],
];
foreach ($pairs as [$a, $b]) {
    $dist = StringProcessor::levenshteinDistance($a, $b);
    echo "  '$a' → '$b': $dist\n";
}

echo "\n--- Soundex ---\n";
$names = ['Robert', 'Rupert', 'Ashcraft', 'Tymczak', 'Pfister', 'Honeyman'];
foreach ($names as $name) {
    echo "  $name → " . StringProcessor::soundex($name) . "\n";
}

echo "\n--- Template Rendering ---\n";
$tpl = <<<TPL
Hello {{name}}!

{{if showDetails}}
Your age is {{age}} and you live in {{city}}.
{{else}}
Details are hidden.
{{/if}}

Your items:
{{foreach items}}
- {{name}} ({{price}})
{{/foreach}}

Total items: {{itemCount}}
TPL;

$template = new StringTemplate($tpl);
$html = $template->render([
    'name' => 'Alice',
    'showDetails' => true,
    'age' => 30,
    'city' => 'Beijing',
    'items' => [
        ['name' => 'Apple', 'price' => '5.00'],
        ['name' => 'Banana', 'price' => '3.50'],
        ['name' => 'Cherry', 'price' => '12.00'],
    ],
    'itemCount' => 3,
]);
echo $html;

echo "\n--- String Tokenizer ---\n";
$csv = 'name,age,city
Alice,30,Beijing
Bob,25,Shanghai
Charlie,35,Guangzhou';
$lines = explode("\n", $csv);
$headers = str_getcsv(array_shift($lines));
echo "  Headers: " . implode(' | ', $headers) . "\n";
foreach ($lines as $line) {
    $row = array_combine($headers, str_getcsv($line));
    echo "  {$row['name']}: age={$row['age']}, city={$row['city']}\n";
}

echo "\n--- URL Parser ---\n";
$urls = [
    'https://example.com/path/to/page?foo=bar&baz=qux#section',
    'http://user:pass@localhost:8080/api/v1/users',
    'ftp://files.example.com/downloads/file.zip',
];
foreach ($urls as $url) {
    $parts = parse_url($url);
    echo "  $url\n";
    echo "    scheme: " . ($parts['scheme'] ?? '') . "\n";
    echo "    host: " . ($parts['host'] ?? '') . "\n";
    echo "    path: " . ($parts['path'] ?? '') . "\n";
    if (isset($parts['query'])) {
        parse_str($parts['query'], $query);
        echo "    query: " . json_encode($query) . "\n";
    }
}

echo "=== f157 Done ===\n";
