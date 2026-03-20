<?php
// Test 013: Regular expressions and pattern matching
class RegexLab {
    private string $text;

    public function __construct() {
        $this->text = <<<'TEXT'
Hello World! This is a test string.
Email: user@example.com and another@domain.org
Phone: 123-456-7890
IP: 192.168.1.1
Date: 2024-03-15
Price: $19.99
Unicode: 中文测试 日本語 한국어
Numbers: 42, 3.14, 1e10, 0xFF
TEXT;
    }

    public function process(): string {
        $out = "";

        // Preg match
        if (preg_match('/Hello/', $this->text, $matches)) {
            $out .= "preg_match('/Hello/'): found\n";
        }

        // Preg match all
        preg_match_all('/\d+/', $this->text, $allMatches);
        $out .= "preg_match_all('/\\d+/'): " . json_encode($allMatches[0]) . "\n";

        // Preg replace
        $replaced = preg_replace('/\d+/', '#', $this->text);
        $out .= "preg_replace('/\\d+/' -> '#'): " . strlen($replaced) . " chars\n";

        // Preg split
        $parts = preg_split('/[\s,]+/', 'one,two,three four');
        $out .= "preg_split: " . implode('|', $parts) . "\n";

        // Preg grep
        $arr = ['foo', 'bar', 'baz', 'fooBar'];
        $filtered = preg_grep('/^foo/', $arr);
        $out .= "preg_grep('/^foo/'): " . implode(',', $filtered) . "\n";

        // Preg filter
        $filtered2 = preg_filter('/\d/', 'X', ['a1b2', 'c3d4']);
        $out .= "preg_filter: " . implode(',', $filtered2) . "\n";

        // Preg match with offsets
        if (preg_match('/test/', $this->text, $m, PREG_OFFSET_CAPTURE, 10)) {
            $out .= "preg_match with offset: " . $m[0][0] . " at " . $m[0][1] . "\n";
        }

        // Preg callbacks
        $callbackResult = preg_replace_callback('/\d+/', function($m) {
            return (int)$m[0] * 2;
        }, '123');
        $out .= "preg_replace_callback: $callbackResult\n";

        // Preg quote
        $quoted = preg_quote('$150.00 (on sale)');
        $out .= "preg_quote: $quoted\n";

        // PCRE functions
        $out .= "\nPCRE version: " . PCRE_VERSION . "\n";

        // preg_last_error
        $out .= "preg_last_error: " . preg_last_error() . "\n";

        return $out;
    }

    public function patterns(): string {
        $out = "";

        $testStrings = [
            'user@example.com',
            'invalid-email',
            '123.456.789.0',
            '192.168.1.1',
            '+1-234-567-8900',
            'http://example.com',
            'https://example.com/path?query=1',
        ];

        $patterns = [
            'email' => '/^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$/',
            'ip' => '/^\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}$/',
            'url' => '/^https?:\/\/.+$/',
        ];

        foreach ($testStrings as $str) {
            foreach ($patterns as $name => $pattern) {
                if (preg_match($pattern, $str)) {
                    $out .= "'$str' matches $name\n";
                }
            }
        }

        return $out;
    }
}

$lab = new RegexLab();
echo $lab->process();
echo "\n";
echo $lab->patterns();