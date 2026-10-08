<?php
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

foreach (['1e5','-2.5e-3','42','3.14','[1,2]','{"n":1e5}'] as $i => $c) {
  $pj = new JsonParser();
  try { $r = $pj->parseString2($c); echo "case$i OK: ".var_export($r,true)."\n"; }
  catch (Throwable $e) { echo "case$i ERR: ".$e->getMessage()."\n"; }
}
