<?php
// Test 009: JSON encode/decode, serialization, and debug functions
class SerializationLab {
    private array $data;

    public function __construct() {
        $this->data = [
            'string' => 'hello',
            'int' => 42,
            'float' => 3.14159,
            'bool' => true,
            'null' => null,
            'array' => [1, 2, 3],
            'nested' => ['a' => ['b' => ['c' => 'deep']]],
            'unicode' => '中文测试',
            'special' => "line1\nline2\ttab",
        ];
    }

    public function process(): string {
        $out = "";

        // JSON encode with various flags
        $out .= "JSON_DEFAULT: " . json_encode($this->data) . "\n";
        $out .= "JSON_PRETTY: " . json_encode($this->data, JSON_PRETTY_PRINT) . "\n";
        $out .= "JSON_UNESCAPED_UNICODE: " . json_encode($this->data, JSON_UNESCAPED_UNICODE) . "\n";
        $out .= "JSON_UNESCAPED_SLASHES: " . json_encode($this->data, JSON_UNESCAPED_SLASHES) . "\n";

        // JSON decode
        $json_str = '{"name":"test","value":123}';
        $decoded = json_decode($json_str, true);
        $out .= "Decoded: " . json_encode($decoded) . "\n";
        $out .= "Decoded name: " . ($decoded['name'] ?? 'null') . "\n";

        // JSON error handling
        $invalid = '{"bad": json}';
        json_decode($invalid);
        $out .= "JSON last error: " . json_last_error() . "\n";
        $out .= "JSON error msg: " . json_last_error_msg() . "\n";

        // Serialize
        $serialized = serialize($this->data);
        $out .= "Serialized length: " . strlen($serialized) . "\n";

        // Unserialize
        $unserialized = unserialize($serialized);
        $out .= "Unserialized: " . (json_encode($unserialized) === json_encode($this->data) ? 'equal' : 'not equal') . "\n";

        // Var export
        $out .= "Var_export: " . var_export($this->data, true) . "\n";

        // Var dump
        $out .= "Var_dump (1, 2.5, true, 'str'): ";
        ob_start();
        var_dump(1, 2.5, true, 'str');
        $out .= ob_get_clean();

        return $out;
    }

    public function debugFunctions(): string {
        $out = "";

        // Debug_zval_dump
        $var = 'test';
        $out .= "Debug_zval_dump: ";
        ob_start();
        debug_zval_dump($var);
        $out .= ob_get_clean();

        // Memory usage
        $out .= "Memory usage: " . memory_get_usage() . " bytes\n";
        $out .= "Peak memory: " . memory_get_peak_usage() . " bytes\n";

        // Debug backtrace
        $out .= "Has debug_backtrace: " . (function_exists('debug_backtrace') ? 'yes' : 'no') . "\n";

        return $out;
    }
}

$lab = new SerializationLab();
echo $lab->process();
echo "\n";
echo $lab->debugFunctions();