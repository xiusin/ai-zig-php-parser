<?php
// 极度混搭: 压缩算法 + Huffman + RLE + LZ77简化 + 解压缩验证
echo "=== f071: Compression + Huffman + RLE + LZ77 ===\n";

class HuffmanNode {
    public ?HuffmanNode $left = null;
    public ?HuffmanNode $right = null;
    public function __construct(public ?string $char = null, public int $freq = 0) {}
}

class Huffman {
    private array $codes = [];

    public function compress(string $data): array {
        if ($data === '') return ['tree' => null, 'codes' => [], 'encoded' => ''];
        // 统计频率
        $freq = [];
        $len = strlen($data);
        for ($i = 0; $i < $len; $i++) {
            $char = $data[$i];
            $freq[$char] = ($freq[$char] ?? 0) + 1;
        }

        // 构建优先队列
        $nodes = [];
        foreach ($freq as $char => $f) {
            $nodes[] = new HuffmanNode($char, $f);
        }

        // 构建树
        while (count($nodes) > 1) {
            usort($nodes, fn($a, $b) => $a->freq <=> $b->freq);
            $left = array_shift($nodes);
            $right = array_shift($nodes);
            $parent = new HuffmanNode(null, $left->freq + $right->freq);
            $parent->left = $left;
            $parent->right = $right;
            $nodes[] = $parent;
        }
        $root = $nodes[0];

        // 生成编码
        $this->codes = [];
        $this->generateCodes($root, '');

        // 编码
        $encoded = '';
        for ($i = 0; $i < $len; $i++) {
            $encoded .= $this->codes[$data[$i]];
        }

        return ['tree' => $root, 'codes' => $this->codes, 'encoded' => $encoded];
    }

    private function generateCodes(?HuffmanNode $node, string $code): void {
        if ($node === null) return;
        if ($node->char !== null) {
            $this->codes[$node->char] = $code !== '' ? $code : '0';
            return;
        }
        $this->generateCodes($node->left, $code . '0');
        $this->generateCodes($node->right, $code . '1');
    }

    public function decompress(string $encoded, array $codes): string {
        if ($encoded === '') return '';
        $reverseCodes = array_flip($codes);
        $result = '';
        $buffer = '';
        $len = strlen($encoded);
        for ($i = 0; $i < $len; $i++) {
            $buffer .= $encoded[$i];
            if (isset($reverseCodes[$buffer])) {
                $result .= $reverseCodes[$buffer];
                $buffer = '';
            }
        }
        return $result;
    }
}

class RunLengthEncoding {
    public static function compress(string $data): string {
        $result = '';
        $len = strlen($data);
        $i = 0;
        while ($i < $len) {
            $char = $data[$i];
            $count = 1;
            while ($i + $count < $len && $data[$i + $count] === $char && $count < 9) {
                $count++;
            }
            $result .= $char . $count;
            $i += $count;
        }
        return $result;
    }

    public static function decompress(string $data): string {
        $result = '';
        $len = strlen($data);
        $i = 0;
        while ($i < $len) {
            $char = $data[$i];
            $count = (int)($data[$i + 1] ?? '1');
            $result .= str_repeat($char, $count);
            $i += 2;
        }
        return $result;
    }
}

class LZ77 {
    public static function compress(string $data, int $windowSize = 16): array {
        $result = [];
        $len = strlen($data);
        $pos = 0;
        while ($pos < $len) {
            $bestOffset = 0; $bestLength = 0;
            $start = max(0, $pos - $windowSize);
            for ($offset = $pos - 1; $offset >= $start; $offset--) {
                $length = 0;
                while ($pos + $length < $len && $data[$offset + $length] === $data[$pos + $length]) {
                    $length++;
                    if ($offset + $length >= $pos) break; // 防止无限循环
                }
                if ($length > $bestLength) {
                    $bestLength = $length;
                    $bestOffset = $pos - $offset;
                }
            }
            if ($bestLength > 0) {
                $nextChar = $pos + $bestLength < $len ? $data[$pos + $bestLength] : '';
                $result[] = ['offset' => $bestOffset, 'length' => $bestLength, 'next' => $nextChar];
                $pos += $bestLength + 1;
            } else {
                $result[] = ['offset' => 0, 'length' => 0, 'next' => $data[$pos]];
                $pos++;
            }
        }
        return $result;
    }

    public static function decompress(array $compressed): string {
        $result = '';
        foreach ($compressed as $entry) {
            if ($entry['length'] > 0) {
                $start = strlen($result) - $entry['offset'];
                for ($i = 0; $i < $entry['length']; $i++) {
                    $result .= $result[$start + $i];
                }
            }
            if ($entry['next'] !== '') $result .= $entry['next'];
        }
        return $result;
    }
}

// 测试
echo "--- Huffman Coding ---\n";
$huffman = new Huffman();
$text = "abracadabra";
$result = $huffman->compress($text);
echo "Original: $text (" . strlen($text) * 8 . " bits)\n";
echo "Encoded: {$result['encoded']} (" . strlen($result['encoded']) . " bits)\n";
echo "Codes:\n";
foreach ($result['codes'] as $char => $code) {
    echo "  '$char' → $code\n";
}
$decoded = $huffman->decompress($result['encoded'], $result['codes']);
echo "Decoded: $decoded\n";
echo "Match: " . var_export($text === $decoded, true) . "\n";
$compressionRatio = (strlen($result['encoded']) / (strlen($text) * 8)) * 100;
echo "Compression ratio: " . number_format($compressionRatio, 1) . "%\n";

echo "\n--- RLE ---\n";
$rleTests = ['AAAAABBBCCCCCC', 'aaabbaa', 'xxxxxxxxxxxx', 'abcdef'];
foreach ($rleTests as $t) {
    $compressed = RunLengthEncoding::compress($t);
    $decompressed = RunLengthEncoding::decompress($compressed);
    echo "  '$t' → '$compressed' → '$decompressed' match=" . var_export($t === $decompressed, true) . "\n";
}

echo "\n--- LZ77 ---\n";
$lz77Tests = ['abracadabra', 'abcabcabc', 'aaaaaa', 'hello hello hello'];
foreach ($lz77Tests as $t) {
    $compressed = LZ77::compress($t);
    $decompressed = LZ77::decompress($compressed);
    echo "  '$t' → " . count($compressed) . " tokens → '$decompressed' match=" . var_export($t === $decompressed, true) . "\n";
}

echo "\n--- Compression Comparison ---\n";
$longText = str_repeat("the quick brown fox jumps ", 10);
echo "Text length: " . strlen($longText) . " bytes\n";
echo "RLE: " . strlen(RunLengthEncoding::compress($longText)) . " bytes\n";
$huffResult = $huffman->compress($longText);
echo "Huffman: " . ceil(strlen($huffResult['encoded']) / 8) . " bytes\n";
$lzResult = LZ77::compress($longText);
echo "LZ77: " . count($lzResult) . " tokens\n";

echo "=== f071 Done ===\n";
