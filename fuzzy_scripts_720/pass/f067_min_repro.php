<?php
// 最小复现：隔离 parseObject while(true)+continue 的 codegen 问题
class MinJsonParser {
    private string $json = '';
    private int $pos = 0;
    private int $len = 0;

    public function parse(string $json): mixed {
        $this->json = $json;
        $this->pos = 0;
        $this->len = strlen($json);
        return $this->parseObject();
    }

    private function parseObject(): array {
        $this->pos++; // {
        $obj = [];
        if ($this->json[$this->pos] === '}') { $this->pos++; return $obj; }
        while (true) {
            $key = $this->parseString();
            if ($this->json[$this->pos] !== ':') throw new RuntimeException("Expected ':'");
            $this->pos++;
            $obj[$key] = $this->parseValue();
            if ($this->json[$this->pos] === ',') { $this->pos++; continue; }
            if ($this->json[$this->pos] === '}') { $this->pos++; break; }
            throw new RuntimeException("Expected ',' or '}'");
        }
        return $obj;
    }

    private function parseString(): string {
        if ($this->json[$this->pos] !== '"') throw new RuntimeException("Expected '\"'");
        $this->pos++;
        $result = '';
        while ($this->pos < $this->len) {
            $char = $this->json[$this->pos];
            if ($char === '"') { $this->pos++; return $result; }
            $result .= $char;
            $this->pos++;
        }
        throw new RuntimeException("Unterminated string");
    }

    private function parseValue(): mixed {
        $char = $this->json[$this->pos];
        if ($char === '"') return $this->parseString();
        if ($char === '{') return $this->parseObject();
        // 简单数字
        $start = $this->pos;
        while ($this->pos < $this->len && ctype_digit($this->json[$this->pos])) { $this->pos++; }
        return (int)substr($this->json, $start, $this->pos - $start);
    }
}

$p = new MinJsonParser();
// 测试1: 单个键值对
echo "Test1: ";
var_dump($p->parse('{"a":"1"}'));
echo "\n";

// 测试2: 两个键值对（需要 continue）
echo "Test2: ";
var_dump($p->parse('{"a":"1","b":"2"}'));
echo "\n";

// 测试3: 三个键值对
echo "Test3: ";
var_dump($p->parse('{"a":"1","b":"2","c":"3"}'));
echo "\n";