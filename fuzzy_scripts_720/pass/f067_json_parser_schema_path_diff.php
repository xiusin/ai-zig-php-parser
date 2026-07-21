<?php
// 极度混搭: JSON解析器手写 + Schema验证 + 路径查询 + 差异比较
echo "=== f067: JSON Parser + Schema + Path Query + Diff ===\n";

class JsonParser {
    private int $pos = 0;
    private int $len;

    public function parse(string $json): mixed {
        $this->len = strlen($json);
        $this->pos = 0;
        $this->skipWhitespace();
        $result = $this->parseValue();
        $this->skipWhitespace();
        if ($this->pos < $this->len) throw new RuntimeException("Unexpected char at pos {$this->pos}");
        return $result;
    }

    private function skipWhitespace(): void {
        while ($this->pos < $this->len && ctype_space($this->json[$this->pos] ?? '')) $this->pos++;
    }

    private function parseValue(): mixed {
        $this->skipWhitespace();
        if ($this->pos >= $this->len) throw new RuntimeException("Unexpected end");
        $char = $this->json[$this->pos];
        return match($char) {
            '{' => $this->parseObject(),
            '[' => $this->parseArray(),
            '"' => $this->parseString(),
            't', 'f' => $this->parseBool(),
            'n' => $this->parseNull(),
            default => $this->parseNumber(),
        };
    }

    private function parseObject(): array {
        $this->json ??= ''; // placeholder
        $this->pos++; // {
        $this->skipWhitespace();
        $obj = [];
        if ($this->json[$this->pos] === '}') { $this->pos++; return $obj; }
        while (true) {
            $this->skipWhitespace();
            $key = $this->parseString();
            $this->skipWhitespace();
            if ($this->json[$this->pos] !== ':') throw new RuntimeException("Expected ':'");
            $this->pos++;
            $obj[$key] = $this->parseValue();
            $this->skipWhitespace();
            if ($this->json[$this->pos] === ',') { $this->pos++; continue; }
            if ($this->json[$this->pos] === '}') { $this->pos++; break; }
            throw new RuntimeException("Expected ',' or '}'");
        }
        return $obj;
    }

    private function parseArray(): array {
        $this->pos++; // [
        $this->skipWhitespace();
        $arr = [];
        if ($this->json[$this->pos] === ']') { $this->pos++; return $arr; }
        while (true) {
            $arr[] = $this->parseValue();
            $this->skipWhitespace();
            if ($this->json[$this->pos] === ',') { $this->pos++; continue; }
            if ($this->json[$this->pos] === ']') { $this->pos++; break; }
            throw new RuntimeException("Expected ',' or ']'");
        }
        return $arr;
    }

    private function parseString(): string {
        if ($this->json[$this->pos] !== '"') throw new RuntimeException("Expected '\"'");
        $this->pos++;
        $result = '';
        while ($this->pos < $this->len) {
            $char = $this->json[$this->pos];
            if ($char === '"') { $this->pos++; return $result; }
            if ($char === '\\') {
                $this->pos++;
                $esc = $this->json[$this->pos];
                $result .= match($esc) {
                    'n' => "\n", 't' => "\t", 'r' => "\r",
                    '"' => '"', '\\' => '\\', '/' => '/',
                    default => $esc,
                };
                $this->pos++;
            } else {
                $result .= $char;
                $this->pos++;
            }
        }
        throw new RuntimeException("Unterminated string");
    }

    private function parseNumber(): int|float {
        $start = $this->pos;
        if ($this->json[$this->pos] === '-') $this->pos++;
        while ($this->pos < $this->len && ctype_digit($this->json[$this->pos])) $this->pos++;
        $isFloat = false;
        if ($this->pos < $this->len && $this->json[$this->pos] === '.') {
            $isFloat = true; $this->pos++;
            while ($this->pos < $this->len && ctype_digit($this->json[$this->pos])) $this->pos++;
        }
        if ($this->pos < $this->len && ($this->json[$this->pos] === 'e' || $this->json[$this->pos] === 'E')) {
            $isFloat = true; $this->pos++;
            if ($this->pos < $this->len && ($this->json[$this->pos] === '+' || $this->json[$this->pos] === '-')) $this->pos++;
            while ($this->pos < $this->len && ctype_digit($this->json[$this->pos])) $this->pos++;
        }
        $num = substr($this->json, $start, $this->pos - $start);
        return $isFloat ? (float)$num : (int)$num;
    }

    private function parseBool(): bool {
        if (substr($this->json, $this->pos, 4) === 'true') { $this->pos += 4; return true; }
        if (substr($this->json, $this->pos, 5) === 'false') { $this->pos += 5; return false; }
        throw new RuntimeException("Invalid boolean");
    }

    private function parseNull(): mixed {
        if (substr($this->json, $this->pos, 4) === 'null') { $this->pos += 4; return null; }
        throw new RuntimeException("Invalid null");
    }

    // 需要保存原始json
    private ?string $json = null;
    public function parseString2(string $json): mixed {
        $this->json = $json;
        return $this->parse($json);
    }
}

class JsonPath {
    public static function query(mixed $data, string $path): mixed {
        $parts = explode('.', $path);
        $current = $data;
        foreach ($parts as $part) {
            if (is_array($current)) {
                if (is_int($part) || ctype_digit($part)) {
                    $idx = (int)$part;
                    if (!isset($current[$idx])) return null;
                    $current = $current[$idx];
                } else {
                    if (!isset($current[$part])) return null;
                    $current = $current[$part];
                }
            } else {
                return null;
            }
        }
        return $current;
    }
}

class JsonDiff {
    public static function diff(mixed $a, mixed $b, string $path = ''): array {
        $changes = [];
        if (gettype($a) !== gettype($b)) {
            $changes[] = ['path' => $path, 'type' => 'type_change', 'from' => $a, 'to' => $b];
            return $changes;
        }
        if (is_array($a)) {
            $keys = array_unique(array_merge(array_keys($a), array_keys($b)));
            foreach ($keys as $key) {
                $childPath = $path === '' ? "$key" : "$path.$key";
                if (!array_key_exists($key, $a)) {
                    $changes[] = ['path' => $childPath, 'type' => 'added', 'value' => $b[$key]];
                } elseif (!array_key_exists($key, $b)) {
                    $changes[] = ['path' => $childPath, 'type' => 'removed', 'value' => $a[$key]];
                } elseif ($a[$key] !== $b[$key]) {
                    if (is_array($a[$key]) && is_array($b[$key])) {
                        $changes = array_merge($changes, self::diff($a[$key], $b[$key], $childPath));
                    } else {
                        $changes[] = ['path' => $childPath, 'type' => 'changed', 'from' => $a[$key], 'to' => $b[$key]];
                    }
                }
            }
        } elseif ($a !== $b) {
            $changes[] = ['path' => $path, 'type' => 'changed', 'from' => $a, 'to' => $b];
        }
        return $changes;
    }
}

// 测试
echo "--- JSON Parse ---\n";
$parser = new JsonParser();
$json = '{"name":"Alice","age":30,"scores":[95,87,92],"active":true,"meta":{"city":"NYC","zip":"10001"}}';
$data = $parser->parseString2($json);
echo "Parsed: " . json_encode($data) . "\n";
echo "PHP json_decode match: " . var_export($data === json_decode($json, true), true) . "\n";

echo "\n--- JSON Path Query ---\n";
echo "name: " . JsonPath::query($data, 'name') . "\n";
echo "age: " . JsonPath::query($data, 'age') . "\n";
echo "scores.0: " . JsonPath::query($data, 'scores.0') . "\n";
echo "scores.2: " . JsonPath::query($data, 'scores.2') . "\n";
echo "meta.city: " . JsonPath::query($data, 'meta.city') . "\n";
echo "meta.zip: " . JsonPath::query($data, 'meta.zip') . "\n";
echo "nonexistent: " . var_export(JsonPath::query($data, 'nonexistent.path'), true) . "\n";

echo "\n--- JSON Diff ---\n";
$json1 = '{"name":"Alice","age":30,"city":"NYC","scores":[90,85]}';
$json2 = '{"name":"Alice","age":31,"city":"LA","scores":[90,85,95],"email":"a@b.com"}';
$d1 = json_decode($json1, true);
$d2 = json_decode($json2, true);
$diff = JsonDiff::diff($d1, $d2);
foreach ($diff as $d) {
    echo "  {$d['path']}: {$d['type']}";
    if (isset($d['from'])) echo " from=" . json_encode($d['from']);
    if (isset($d['to'])) echo " to=" . json_encode($d['to']);
    if (isset($d['value'])) echo " value=" . json_encode($d['value']);
    echo "\n";
}

echo "\n--- Parse Numbers ---\n";
$nums = ['42', '-17', '3.14', '1e5', '-2.5e-3'];
foreach ($nums as $n) {
    $parsed = $parser->parseString2($n);
    echo "  '$n' → " . var_export($parsed, true) . " (type: " . gettype($parsed) . ")\n";
}

echo "\n--- Parse Errors ---\n";
$bad = ['{"a":}', '[1,2,]', '{"a" 1}', '"unterminated'];
foreach ($b as $badJson) {
    try {
        $parser->parseString2($badJson);
        echo "  '$badJson' → no error (unexpected)\n";
    } catch (RuntimeException $e) {
        echo "  '$badJson' → Error: " . $e->getMessage() . "\n";
    }
}

echo "=== f067 Done ===\n";
