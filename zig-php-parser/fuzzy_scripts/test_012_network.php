<?php
// Test 012: Network functions, sockets, and HTTP-like operations
class NetworkLab {
    public function process(): string {
        $out = "";

        // Check if functions exist
        $out .= "Function checks:\n";
        $out .= "  fsockopen exists: " . (function_exists('fsockopen') ? 'yes' : 'no') . "\n";
        $out .= "  stream_socket_client exists: " . (function_exists('stream_socket_client') ? 'yes' : 'no') . "\n";
        $out .= "  curl_init exists: " . (function_exists('curl_init') ? 'yes' : 'no') . "\n";
        $out .= "  gethostbyname exists: " . (function_exists('gethostbyname') ? 'yes' : 'no') . "\n";
        $out .= "  getmxrr exists: " . (function_exists('getmxrr') ? 'yes' : 'no') . "\n";
        $out .= "  checkdnsrr exists: " . (function_exists('checkdnsrr') ? 'yes' : 'no') . "\n";

        // DNS functions
        $localhost = gethostbyname('localhost');
        $out .= "\ngethostbyname('localhost'): $localhost\n";

        $hostname = gethostname();
        $out .= "gethostname(): $hostname\n";

        // IP address functions
        $out .= "ip2long('127.0.0.1'): " . ip2long('127.0.0.1') . "\n";
        $out .= "long2ip(2130706433): " . long2ip(2130706433) . "\n";

        // URL parse
        $url = 'https://user:pass@example.com:8080/path?query=value#anchor';
        $parts = parse_url($url);
        $out .= "\nparse_url('$url'):\n";
        foreach ($parts as $key => $value) {
            $out .= "  $key: $value\n";
        }

        // URL encode/decode
        $out .= "\nurlencode('hello world'): " . urlencode('hello world') . "\n";
        $out .= "urldecode('hello+world'): " . urldecode('hello+world') . "\n";
        $out .= "rawurlencode('hello world'): " . rawurlencode('hello world') . "\n";

        // HTTP build query
        $data = ['foo' => 'bar', 'baz' => 'qux', 'arr' => [1, 2]];
        $out .= "http_build_query: " . http_build_query($data) . "\n";

        // Header functions
        $out .= "\nheader functions exist: " . (function_exists('header') ? 'yes' : 'no') . "\n";
        $out .= "headers_list: " . json_encode(headers_list()) . "\n";

        // Stream functions
        $out .= "\nstream_socket_client exists: " . (function_exists('stream_socket_client') ? 'yes' : 'no') . "\n";
        $out .= "stream_context_create exists: " . (function_exists('stream_context_create') ? 'yes' : 'no') . "\n";

        return $out;
    }
}

$lab = new NetworkLab();
echo $lab->process();