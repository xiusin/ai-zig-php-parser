<?php
/**
 * 字符串操作性能测试
 * 
 * 测试所有 80+ 字符串函数的性能
 * 迭代次数：10,000 次
 * 
 * 测试分类：
 * 1. 基本字符串操作
 * 2. 字符串搜索和替换
 * 3. 字符串格式化
 * 4. 字符串编码和解码
 * 5. 字符串比较
 * 6. 字符串分割和连接
 */

// 配置
const ITERATIONS = 10000;

// 测试数据
const SHORT_STRING = "Hello, World!";
const LONG_STRING = "Lorem ipsum dolor sit amet, consectetur adipiscing elit. Sed do eiusmod tempor incididunt ut labore et dolore magna aliqua. Ut enim ad minim veniam, quis nostrud exercitation ullamco laboris nisi ut aliquip ex ea commodo consequat.";
const PATTERN = "dolor";
const REPLACEMENT = "DOLOR";

// ============================================================================
// 1. 基本字符串操作
// ============================================================================

function test_strlen() {
    $result = 0;
    for ($i = 0; $i < ITERATIONS; $i++) {
        $result += strlen(SHORT_STRING);
        $result += strlen(LONG_STRING);
    }
    return $result;
}

function test_substr() {
    $result = "";
    for ($i = 0; $i < ITERATIONS; $i++) {
        $result = substr(LONG_STRING, 0, 10);
        $result = substr(LONG_STRING, -10);
    }
    return strlen($result);
}

function test_str_repeat() {
    $result = "";
    for ($i = 0; $i < ITERATIONS; $i++) {
        $result = str_repeat("x", 10);
    }
    return strlen($result);
}

function test_str_pad() {
    $result = "";
    for ($i = 0; $i < ITERATIONS; $i++) {
        $result = str_pad(SHORT_STRING, 20, "*");
    }
    return strlen($result);
}

function test_strtoupper() {
    $result = "";
    for ($i = 0; $i < ITERATIONS; $i++) {
        $result = strtoupper(LONG_STRING);
    }
    return strlen($result);
}

function test_strtolower() {
    $result = "";
    for ($i = 0; $i < ITERATIONS; $i++) {
        $result = strtolower(LONG_STRING);
    }
    return strlen($result);
}

function test_ucfirst() {
    $result = "";
    for ($i = 0; $i < ITERATIONS; $i++) {
        $result = ucfirst(SHORT_STRING);
    }
    return strlen($result);
}

function test_lcfirst() {
    $result = "";
    for ($i = 0; $i < ITERATIONS; $i++) {
        $result = lcfirst(SHORT_STRING);
    }
    return strlen($result);
}

function test_ucwords() {
    $result = "";
    for ($i = 0; $i < ITERATIONS; $i++) {
        $result = ucwords(LONG_STRING);
    }
    return strlen($result);
}

// ============================================================================
// 2. 字符串搜索和替换
// ============================================================================

function test_strpos() {
    $result = 0;
    for ($i = 0; $i < ITERATIONS; $i++) {
        $pos = strpos(LONG_STRING, PATTERN);
        $result += ($pos !== false) ? $pos : 0;
    }
    return $result;
}

function test_strrpos() {
    $result = 0;
    for ($i = 0; $i < ITERATIONS; $i++) {
        $pos = strrpos(LONG_STRING, "a");
        $result += ($pos !== false) ? $pos : 0;
    }
    return $result;
}

function test_strstr() {
    $result = "";
    for ($i = 0; $i < ITERATIONS; $i++) {
        $result = strstr(LONG_STRING, PATTERN);
    }
    return strlen($result);
}

function test_stristr() {
    $result = "";
    for ($i = 0; $i < ITERATIONS; $i++) {
        $result = stristr(LONG_STRING, "DOLOR");
    }
    return strlen($result);
}

function test_str_replace() {
    $result = "";
    for ($i = 0; $i < ITERATIONS; $i++) {
        $result = str_replace(PATTERN, REPLACEMENT, LONG_STRING);
    }
    return strlen($result);
}

function test_str_ireplace() {
    $result = "";
    for ($i = 0; $i < ITERATIONS; $i++) {
        $result = str_ireplace("DOLOR", REPLACEMENT, LONG_STRING);
    }
    return strlen($result);
}

function test_substr_replace() {
    $result = "";
    for ($i = 0; $i < ITERATIONS; $i++) {
        $result = substr_replace(LONG_STRING, "***", 10, 5);
    }
    return strlen($result);
}

function test_substr_count() {
    $result = 0;
    for ($i = 0; $i < ITERATIONS; $i++) {
        $result += substr_count(LONG_STRING, "a");
    }
    return $result;
}

// ============================================================================
// 3. 字符串格式化
// ============================================================================

function test_sprintf() {
    $result = "";
    for ($i = 0; $i < ITERATIONS; $i++) {
        $result = sprintf("Number: %d, String: %s", $i, SHORT_STRING);
    }
    return strlen($result);
}

function test_vsprintf() {
    $result = "";
    for ($i = 0; $i < ITERATIONS; $i++) {
        $result = vsprintf("Number: %d, String: %s", [$i, SHORT_STRING]);
    }
    return strlen($result);
}

function test_number_format() {
    $result = "";
    for ($i = 0; $i < ITERATIONS; $i++) {
        $result = number_format(1234567.89, 2, '.', ',');
    }
    return strlen($result);
}

function test_wordwrap() {
    $result = "";
    for ($i = 0; $i < ITERATIONS; $i++) {
        $result = wordwrap(LONG_STRING, 50, "\n");
    }
    return strlen($result);
}

// ============================================================================
// 4. 字符串编码和解码
// ============================================================================

function test_base64_encode() {
    $result = "";
    for ($i = 0; $i < ITERATIONS; $i++) {
        $result = base64_encode(LONG_STRING);
    }
    return strlen($result);
}

function test_base64_decode() {
    $encoded = base64_encode(LONG_STRING);
    $result = "";
    for ($i = 0; $i < ITERATIONS; $i++) {
        $result = base64_decode($encoded);
    }
    return strlen($result);
}

function test_urlencode() {
    $result = "";
    for ($i = 0; $i < ITERATIONS; $i++) {
        $result = urlencode(SHORT_STRING);
    }
    return strlen($result);
}

function test_urldecode() {
    $encoded = urlencode(SHORT_STRING);
    $result = "";
    for ($i = 0; $i < ITERATIONS; $i++) {
        $result = urldecode($encoded);
    }
    return strlen($result);
}

function test_htmlspecialchars() {
    $html = "<p>Hello & goodbye</p>";
    $result = "";
    for ($i = 0; $i < ITERATIONS; $i++) {
        $result = htmlspecialchars($html);
    }
    return strlen($result);
}

function test_htmlentities() {
    $html = "<p>Hello & goodbye</p>";
    $result = "";
    for ($i = 0; $i < ITERATIONS; $i++) {
        $result = htmlentities($html);
    }
    return strlen($result);
}

function test_html_entity_decode() {
    $encoded = htmlentities("<p>Hello & goodbye</p>");
    $result = "";
    for ($i = 0; $i < ITERATIONS; $i++) {
        $result = html_entity_decode($encoded);
    }
    return strlen($result);
}

// ============================================================================
// 5. 字符串比较
// ============================================================================

function test_strcmp() {
    $result = 0;
    for ($i = 0; $i < ITERATIONS; $i++) {
        $result += strcmp(SHORT_STRING, "Hello, World!");
        $result += strcmp(SHORT_STRING, "hello, world!");
    }
    return $result;
}

function test_strcasecmp() {
    $result = 0;
    for ($i = 0; $i < ITERATIONS; $i++) {
        $result += strcasecmp(SHORT_STRING, "hello, world!");
    }
    return $result;
}

function test_strncmp() {
    $result = 0;
    for ($i = 0; $i < ITERATIONS; $i++) {
        $result += strncmp(SHORT_STRING, "Hello", 5);
    }
    return $result;
}

function test_strnatcmp() {
    $result = 0;
    for ($i = 0; $i < ITERATIONS; $i++) {
        $result += strnatcmp("file10.txt", "file2.txt");
    }
    return $result;
}

function test_levenshtein() {
    $result = 0;
    for ($i = 0; $i < ITERATIONS; $i++) {
        $result += levenshtein("kitten", "sitting");
    }
    return $result;
}

function test_similar_text() {
    $result = 0;
    for ($i = 0; $i < ITERATIONS; $i++) {
        $result += similar_text("Hello World", "Hello PHP");
    }
    return $result;
}

// ============================================================================
// 6. 字符串分割和连接
// ============================================================================

function test_explode() {
    $result = [];
    for ($i = 0; $i < ITERATIONS; $i++) {
        $result = explode(" ", LONG_STRING);
    }
    return count($result);
}

function test_implode() {
    $array = explode(" ", LONG_STRING);
    $result = "";
    for ($i = 0; $i < ITERATIONS; $i++) {
        $result = implode(" ", $array);
    }
    return strlen($result);
}

function test_str_split() {
    $result = [];
    for ($i = 0; $i < ITERATIONS; $i++) {
        $result = str_split(SHORT_STRING, 2);
    }
    return count($result);
}

function test_chunk_split() {
    $result = "";
    for ($i = 0; $i < ITERATIONS; $i++) {
        $result = chunk_split(LONG_STRING, 10, "\n");
    }
    return strlen($result);
}

// ============================================================================
// 7. 字符串修剪
// ============================================================================

function test_trim() {
    $padded = "  " . SHORT_STRING . "  ";
    $result = "";
    for ($i = 0; $i < ITERATIONS; $i++) {
        $result = trim($padded);
    }
    return strlen($result);
}

function test_ltrim() {
    $padded = "  " . SHORT_STRING;
    $result = "";
    for ($i = 0; $i < ITERATIONS; $i++) {
        $result = ltrim($padded);
    }
    return strlen($result);
}

function test_rtrim() {
    $padded = SHORT_STRING . "  ";
    $result = "";
    for ($i = 0; $i < ITERATIONS; $i++) {
        $result = rtrim($padded);
    }
    return strlen($result);
}

function test_chop() {
    $padded = SHORT_STRING . "  ";
    $result = "";
    for ($i = 0; $i < ITERATIONS; $i++) {
        $result = chop($padded);
    }
    return strlen($result);
}

// ============================================================================
// 8. 其他字符串函数
// ============================================================================

function test_str_shuffle() {
    $result = "";
    for ($i = 0; $i < ITERATIONS; $i++) {
        $result = str_shuffle(SHORT_STRING);
    }
    return strlen($result);
}

function test_strrev() {
    $result = "";
    for ($i = 0; $i < ITERATIONS; $i++) {
        $result = strrev(LONG_STRING);
    }
    return strlen($result);
}

function test_str_word_count() {
    $result = 0;
    for ($i = 0; $i < ITERATIONS; $i++) {
        $result += str_word_count(LONG_STRING);
    }
    return $result;
}

function test_count_chars() {
    $result = [];
    for ($i = 0; $i < ITERATIONS; $i++) {
        $result = count_chars(SHORT_STRING, 1);
    }
    return count($result);
}

function test_md5() {
    $result = "";
    for ($i = 0; $i < ITERATIONS; $i++) {
        $result = md5(LONG_STRING);
    }
    return strlen($result);
}

function test_sha1() {
    $result = "";
    for ($i = 0; $i < ITERATIONS; $i++) {
        $result = sha1(LONG_STRING);
    }
    return strlen($result);
}

function test_crc32() {
    $result = 0;
    for ($i = 0; $i < ITERATIONS; $i++) {
        $result = crc32(LONG_STRING);
    }
    return $result;
}

function test_str_rot13() {
    $result = "";
    for ($i = 0; $i < ITERATIONS; $i++) {
        $result = str_rot13(LONG_STRING);
    }
    return strlen($result);
}

function test_addslashes() {
    $text = "It's a \"test\"";
    $result = "";
    for ($i = 0; $i < ITERATIONS; $i++) {
        $result = addslashes($text);
    }
    return strlen($result);
}

function test_stripslashes() {
    $text = addslashes("It's a \"test\"");
    $result = "";
    for ($i = 0; $i < ITERATIONS; $i++) {
        $result = stripslashes($text);
    }
    return strlen($result);
}

function test_quotemeta() {
    $text = "Hello. How are you?";
    $result = "";
    for ($i = 0; $i < ITERATIONS; $i++) {
        $result = quotemeta($text);
    }
    return strlen($result);
}

function test_nl2br() {
    $text = "Line 1\nLine 2\nLine 3";
    $result = "";
    for ($i = 0; $i < ITERATIONS; $i++) {
        $result = nl2br($text);
    }
    return strlen($result);
}

function test_strip_tags() {
    $html = "<p>Hello <b>World</b></p>";
    $result = "";
    for ($i = 0; $i < ITERATIONS; $i++) {
        $result = strip_tags($html);
    }
    return strlen($result);
}

function test_parse_str() {
    $query = "name=John&age=30&city=NewYork";
    $result = [];
    for ($i = 0; $i < ITERATIONS; $i++) {
        parse_str($query, $result);
    }
    return count($result);
}

function test_http_build_query() {
    $data = ['name' => 'John', 'age' => 30, 'city' => 'NewYork'];
    $result = "";
    for ($i = 0; $i < ITERATIONS; $i++) {
        $result = http_build_query($data);
    }
    return strlen($result);
}

// ============================================================================
// 主测试运行器
// ============================================================================

function run_all_tests() {
    $tests = [
        // 基本操作
        'strlen' => 'test_strlen',
        'substr' => 'test_substr',
        'str_repeat' => 'test_str_repeat',
        'str_pad' => 'test_str_pad',
        'strtoupper' => 'test_strtoupper',
        'strtolower' => 'test_strtolower',
        'ucfirst' => 'test_ucfirst',
        'lcfirst' => 'test_lcfirst',
        'ucwords' => 'test_ucwords',
        
        // 搜索和替换
        'strpos' => 'test_strpos',
        'strrpos' => 'test_strrpos',
        'strstr' => 'test_strstr',
        'stristr' => 'test_stristr',
        'str_replace' => 'test_str_replace',
        'str_ireplace' => 'test_str_ireplace',
        'substr_replace' => 'test_substr_replace',
        'substr_count' => 'test_substr_count',
        
        // 格式化
        'sprintf' => 'test_sprintf',
        'vsprintf' => 'test_vsprintf',
        'number_format' => 'test_number_format',
        'wordwrap' => 'test_wordwrap',
        
        // 编码解码
        'base64_encode' => 'test_base64_encode',
        'base64_decode' => 'test_base64_decode',
        'urlencode' => 'test_urlencode',
        'urldecode' => 'test_urldecode',
        'htmlspecialchars' => 'test_htmlspecialchars',
        'htmlentities' => 'test_htmlentities',
        'html_entity_decode' => 'test_html_entity_decode',
        
        // 比较
        'strcmp' => 'test_strcmp',
        'strcasecmp' => 'test_strcasecmp',
        'strncmp' => 'test_strncmp',
        'strnatcmp' => 'test_strnatcmp',
        'levenshtein' => 'test_levenshtein',
        'similar_text' => 'test_similar_text',
        
        // 分割连接
        'explode' => 'test_explode',
        'implode' => 'test_implode',
        'str_split' => 'test_str_split',
        'chunk_split' => 'test_chunk_split',
        
        // 修剪
        'trim' => 'test_trim',
        'ltrim' => 'test_ltrim',
        'rtrim' => 'test_rtrim',
        'chop' => 'test_chop',
        
        // 其他
        'str_shuffle' => 'test_str_shuffle',
        'strrev' => 'test_strrev',
        'str_word_count' => 'test_str_word_count',
        'count_chars' => 'test_count_chars',
        'md5' => 'test_md5',
        'sha1' => 'test_sha1',
        'crc32' => 'test_crc32',
        'str_rot13' => 'test_str_rot13',
        'addslashes' => 'test_addslashes',
        'stripslashes' => 'test_stripslashes',
        'quotemeta' => 'test_quotemeta',
        'nl2br' => 'test_nl2br',
        'strip_tags' => 'test_strip_tags',
        'parse_str' => 'test_parse_str',
        'http_build_query' => 'test_http_build_query',
    ];
    
    $results = [];
    $total_tests = count($tests);
    $current = 0;
    
    echo "总共 " . $total_tests . " 个测试\n\n";
    
    foreach ($tests as $name => $func) {
        $current++;
        echo sprintf("[%3d/%3d] %-30s ... ", $current, $total_tests, $name);
        
        $start = microtime(true);
        $result = call_user_func($func);
        $end = microtime(true);
        
        $time_ms = ($end - $start) * 1000;
        $results[$name] = [
            'time_ms' => $time_ms,
            'result' => $result,
        ];
        
        echo sprintf("%8.3f ms\n", $time_ms);
    }
    
    return $results;
}

// 运行测试
echo "=== 字符串操作性能测试 ===\n";
echo "迭代次数: " . ITERATIONS . "\n";
echo "短字符串长度: " . strlen(SHORT_STRING) . "\n";
echo "长字符串长度: " . strlen(LONG_STRING) . "\n\n";

$results = run_all_tests();

// 统计
$total_time = 0;
foreach ($results as $result) {
    $total_time += $result['time_ms'];
}

echo "\n=== 测试完成 ===\n";
echo sprintf("总耗时: %.3f ms\n", $total_time);
echo sprintf("平均耗时: %.3f ms\n", $total_time / count($results));
