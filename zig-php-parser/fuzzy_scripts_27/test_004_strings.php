<?php
// Test 004: String manipulation and encoding tricks
class StringLab {
    private string $data;

    public function __construct(string $data) {
        $this->data = $data;
    }

    public function process(): string {
        $out = "";

        // Basic operations
        $out .= "Length: " . strlen($this->data) . "\n";
        $out .= "Word count: " . str_word_count($this->data) . "\n";
        $out .= "Reverse: " . strrev($this->data) . "\n";
        $out .= "MD5: " . md5($this->data) . "\n";
        $out .= "SHA1: " . sha1($this->data) . "\n";

        // Position searches
        $out .= "Position of 'test': " . strpos($this->data, 'test') . "\n";
        $out .= "Contains 'foo': " . (str_contains($this->data, 'foo') ? 'yes' : 'no') . "\n";
        $out .= "Starts with 'Hello': " . (str_starts_with($this->data, 'Hello') ? 'yes' : 'no') . "\n";
        $out .= "Ends with 'World': " . (str_ends_with($this->data, 'World') ? 'yes' : 'no') . "\n";

        // Transformations
        $out .= "Upper: " . strtoupper($this->data) . "\n";
        $out .= "Lower: " . strtolower($this->data) . "\n";
        $out .= "Ucfirst: " . ucfirst($this->data) . "\n";
        $out .= "Ucwords: " . ucwords($this->data) . "\n";
        $out .= "Rot13: " . rot13($this->data) . "\n";

        // Trimming
        $out .= "Trim '  test  ': '" . trim("  test  ") . "'\n";
        $out .= "Ltrim: '" . ltrim("  test") . "'\n";
        $out .= "Rtrim: '" . rtrim("test  ") . "'\n";

        // Padding
        $out .= "Str_pad: '" . str_pad("test", 10, "_-", STR_PAD_BOTH) . "'\n";

        // Repeating
        $out .= "Repeat 'ab' 3x: " . str_repeat("ab", 3) . "\n";

        // Chunking
        $chunked = str_chunk("hello", 2);
        $out .= "Chunk 'hello' by 2: " . json_encode($chunked) . "\n";

        return $out;
    }

    public function processMultibyte(): string {
        $out = "";

        // Multibyte strings
        $out .= "MB Length: " . mb_strlen($this->data) . "\n";
        $out .= "MB Position: " . mb_strpos($this->data, '测试') . "\n";
        $out .= "MB Upper: " . mb_strtoupper($this->data) . "\n";
        $out .= "MB Lower: " . mb_strtolower($this->data) . "\n";

        return $out;
    }
}

$tests = [
    "Hello World",
    "  spaces around  ",
    "UPPERCASE",
    "lowercase",
    "MixEd CaSe",
    "With\nNewlines\tAnd\TTabs",
    "Special!@#$%^&*()",
    "Numbers123And456",
    "",
];

$lab = new StringLab("Hello World");
echo $lab->process();
echo "\n";

$lab2 = new StringLab("中文测试 Chinese");
echo $lab2->processMultibyte();