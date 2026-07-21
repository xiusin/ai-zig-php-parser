<?php
// 极度混搭: 数据压缩 + 哈夫曼 + LZ77 + 游程编码 + 算术编码
echo "=== f125: Compression + Huffman + LZ77 + RLE + Arithmetic ===\n";

class RLE {
    public static function compress(string $data): string {
        if ($data === '') return '';
        $result = '';
        $count = 1;
        $prev = $data[0];
        for ($i = 1; $i < strlen($data); $i++) {
            if ($data[$i] === $prev && $count < 255) {
                $count++;
            } else {
                $result .= chr($count) . $prev;
                $prev = $data[$i];
                $count = 1;
            }
        }
        $result .= chr($count) . $prev;
        return $result;
    }

    public static function decompress(string $data): string {
        $result = '';
        for ($i = 0; $i < strlen($data); $i += 2) {
            $count = ord($data[$i]);
            $char = $data[$i + 1] ?? '';
            $result .= str_repeat($char, $count);
        }
        return $result;
    }
}

class HuffmanNode {
    public ?HuffmanNode $left = null;
    public ?HuffmanNode $right = null;
    public function __construct(public string $char = '', public int $freq = 0) {}
    public function isLeaf(): bool { return $this->left === null && $this->right === null; }
}

class Huffman {
    private array $codes = [];

    public function buildTree(array $freqMap): HuffmanNode {
        $nodes = [];
        foreach ($freqMap as $char => $freq) $nodes[] = new HuffmanNode($char, $freq);
        while (count($nodes) > 1) {
            usort($nodes, fn($a, $b) => $a->freq <=> $b->freq);
            $left = array_shift($nodes);
            $right = array_shift($nodes);
            $parent = new HuffmanNode('', $left->freq + $right->freq);
            $parent->left = $left;
            $parent->right = $right;
            $nodes[] = $parent;
        }
        return $nodes[0];
    }

    public function buildCodes(HuffmanNode $root, string $code = ''): void {
        if ($root->isLeaf()) {
            $this->codes[$root->char] = $code !== '' ? $code : '0';
            return;
        }
        $this->buildCodes($root->left, $code . '0');
        $this->buildCodes($root->right, $code . '1');
    }

    public function compress(string $data): string {
        $freqMap = array_count_values(str_split($data));
        $root = $this->buildTree($freqMap);
        $this->buildCodes($root);
        $bits = '';
        for ($i = 0; $i < strlen($data); $i++) $bits .= $this->codes[$data[$i]];
        // Pad to byte boundary
        $padding = (8 - strlen($bits) % 8) % 8;
        $bits .= str_repeat('0', $padding);
        $compressed = chr($padding);
        for ($i = 0; $i < strlen($bits); $i += 8) {
            $compressed .= chr(bindec(substr($bits, $i, 8)));
        }
        return $compressed;
    }

    public function getCodes(): array { return $this->codes; }

    public function getCompressionRatio(string $original, string $compressed): float {
        return strlen($original) > 0 ? strlen($compressed) / strlen($original) : 0;
    }
}

class LZ77 {
    public function compress(string $data, int $windowSize = 256, int $lookAhead = 16): string {
        $result = '';
        $pos = 0;
        while ($pos < strlen($data)) {
            $bestOffset = 0; $bestLength = 0;
            $start = max(0, $pos - $windowSize);
            for ($offset = $pos - 1; $offset >= $start; $offset--) {
                $length = 0;
                while ($length < $lookAhead && $pos + $length < strlen($data) && $data[$offset + $length] === $data[$pos + $length]) {
                    $length++;
                    if ($offset + $length >= $pos) $offset = $offset; // allow overlapping
                }
                if ($length > $bestLength) { $bestLength = $length; $bestOffset = $pos - $offset; }
            }
            if ($bestLength > 2) {
                $nextChar = $data[$pos + $bestLength] ?? '';
                $result .= chr(($bestOffset >> 8) & 0xFF) . chr($bestOffset & 0xFF) . chr($bestLength) . $nextChar;
                $pos += $bestLength + 1;
            } else {
                $result .= "\x00\x00\x00" . $data[$pos];
                $pos++;
            }
        }
        return $result;
    }

    public function decompress(string $data): string {
        $result = '';
        $pos = 0;
        while ($pos < strlen($data)) {
            if ($pos + 3 >= strlen($data)) break;
            $offset = (ord($data[$pos]) << 8) | ord($data[$pos + 1]);
            $length = ord($data[$pos + 2]);
            $char = $data[$pos + 3] ?? '';
            if ($offset > 0 && $length > 0) {
                $startPos = strlen($result) - $offset;
                for ($i = 0; $i < $length; $i++) {
                    $result .= $result[$startPos + $i] ?? '';
                }
            }
            $result .= $char;
            $pos += 4;
        }
        return $result;
    }
}

class ArithmeticCoding {
    public function compress(string $data, array $freqMap): array {
        $total = array_sum($freqMap);
        $low = 0.0; $high = 1.0;
        for ($i = 0; $i < strlen($data); $i++) {
            $char = $data[$i];
            $range = $high - $low;
            $cumFreq = 0;
            foreach ($freqMap as $c => $f) {
                if ($c === $char) break;
                $cumFreq += $f;
            }
            $high = $low + $range * ($cumFreq + $freqMap[$char]) / $total;
            $low = $low + $range * $cumFreq / $total;
        }
        return ['value' => ($low + $high) / 2, 'length' => strlen($data)];
    }
}

// 测试
echo "--- RLE ---\n";
$rleData = "aaabbbcccdddddeeeefffffgg";
$compressed = RLE::compress($rleData);
$decompressed = RLE::decompress($compressed);
echo "Original: $rleData (" . strlen($rleData) . " bytes)\n";
echo "Compressed: " . bin2hex($compressed) . " (" . strlen($compressed) . " bytes)\n";
echo "Decompressed: $decompressed\n";
echo "Match: " . var_export($rleData === $decompressed, true) . "\n";

echo "\n--- Huffman Coding ---\n";
$text = "the quick brown fox jumps over the lazy dog the quick brown fox";
$huffman = new Huffman();
$compressedH = $huffman->compress($text);
$freqMap = array_count_values(str_split($text));
echo "Original: \"$text\" (" . strlen($text) . " bytes)\n";
echo "Compressed: " . strlen($compressedH) . " bytes\n";
echo "Ratio: " . number_format($huffman->getCompressionRatio($text, $compressedH) * 100, 1) . "%\n";
echo "Codes:\n";
foreach ($huffman->getCodes() as $char => $code) {
    $display = $char === ' ' ? '(space)' : $char;
    echo "  '$display': $code (freq={$freqMap[$char]})\n";
}

echo "\n--- LZ77 ---\n";
$lzData = "abcabcabcabcabcabcabcabcabcdefghijabcdefghijabcdefghij";
$lz77 = new LZ77();
$lzCompressed = $lz77->compress($lzData);
$lzDecompressed = $lz77->decompress($lzCompressed);
echo "Original: \"$lzData\" (" . strlen($lzData) . " bytes)\n";
echo "Compressed: " . strlen($lzCompressed) . " bytes\n";
echo "Decompressed: \"$lzDecompressed\"\n";
echo "Match: " . var_export($lzData === $lzDecompressed, true) . "\n";

echo "\n--- Arithmetic Coding ---\n";
$ac = new ArithmeticCoding();
$text2 = "AABABCABCD";
$freqMap2 = array_count_values(str_split($text2));
$result = $ac->compress($text2, $freqMap2);
echo "Text: $text2\n";
echo "Freq map: " . json_encode($freqMap2) . "\n";
echo "Encoded value: " . number_format($result['value'], 15) . "\n";
echo "Length: {$result['length']}\n";

echo "\n--- Compression Comparison ---\n";
$samples = [
    'repetitive' => str_repeat('abc', 50),
    'random' => implode('', array_map(fn() => chr(mt_rand(65, 90)), range(1, 150))),
    'text' => "The quick brown fox jumps over the lazy dog. The quick brown fox jumps over the lazy dog.",
    'binary' => implode('', array_map(fn($i) => chr($i % 256), range(0, 199))),
];
foreach ($samples as $name => $data) {
    $rleSize = strlen(RLE::compress($data));
    $huffSize = strlen($huffman->compress($data));
    $lzSize = strlen($lz77->compress($data));
    $origSize = strlen($data);
    echo "  $name (orig=$origSize): RLE=$rleSize Huffman=$huffSize LZ77=$lzSize\n";
    echo "    Ratios: RLE=" . number_format($rleSize / $origSize * 100, 0) . "% Huffman=" . number_format($huffSize / $origSize * 100, 0) . "% LZ77=" . number_format($lzSize / $origSize * 100, 0) . "%\n";
}

echo "=== f125 Done ===\n";
