<?php
// 验证：filter_var, FILTER_VALIDATE_*, 正则验证

// 测试 filter_var email
echo "email_valid: " . (filter_var('test@example.com', FILTER_VALIDATE_EMAIL) ? 'true' : 'false') . "\n";
echo "email_invalid: " . (filter_var('not-email', FILTER_VALIDATE_EMAIL) ? 'true' : 'false') . "\n";

// 测试 filter_var URL
echo "url_valid: " . (filter_var('https://example.com', FILTER_VALIDATE_URL) ? 'true' : 'false') . "\n";
echo "url_invalid: " . (filter_var('not-url', FILTER_VALIDATE_URL) ? 'true' : 'false') . "\n";

// 测试 filter_var IP
echo "ipv4_valid: " . (filter_var('192.168.1.1', FILTER_VALIDATE_IP) ? 'true' : 'false') . "\n";
echo "ipv4_invalid: " . (filter_var('999.999.999.999', FILTER_VALIDATE_IP) ? 'true' : 'false') . "\n";

// 测试 filter_var INT
echo "int_valid: " . (filter_var('42', FILTER_VALIDATE_INT) ? 'true' : 'false') . "\n";
echo "int_invalid: " . (filter_var('abc', FILTER_VALIDATE_INT) ? 'true' : 'false') . "\n";

// 测试 filter_var FLOAT
echo "float_valid: " . (filter_var('3.14', FILTER_VALIDATE_FLOAT) ? 'true' : 'false') . "\n";

// 测试 filter_var REGEXP
echo "regexp_valid: " . (filter_var('abc123', FILTER_VALIDATE_REGEXP, ['options' => ['regexp' => '/^[a-z0-9]+$/']]) ? 'true' : 'false') . "\n";
echo "regexp_invalid: " . (filter_var('ABC123!', FILTER_VALIDATE_REGEXP, ['options' => ['regexp' => '/^[a-z0-9]+$/']]) ? 'true' : 'false') . "\n";

// 测试自定义验证函数
function validate_phone(string $phone): bool {
    return (bool)preg_match('/^\d{3}-\d{3}-\d{4}$/', $phone);
}

echo "phone_valid: " . (validate_phone('123-456-7890') ? 'true' : 'false') . "\n";
echo "phone_invalid: " . (validate_phone('123-456') ? 'true' : 'false') . "\n";

// 测试 filter_var BOOLEAN
echo "bool_true: " . (filter_var('true', FILTER_VALIDATE_BOOLEAN) ? 'true' : 'false') . "\n";
echo "bool_false: " . (filter_var('0', FILTER_VALIDATE_BOOLEAN) ? 'true' : 'false') . "\n";

// 测试 filter_input 模拟
function validate_required(array $data, array $fields): array {
    $errors = [];
    foreach ($fields as $field) {
        if (!isset($data[$field]) || empty($data[$field])) {
            $errors[] = "$field is required";
        }
    }
    return $errors;
}

$errors = validate_required(
    ['name' => 'Alice', 'email' => ''],
    ['name', 'email']
);
echo "validation_errors: " . count($errors) . "\n";
echo "error_msg: " . $errors[0] . "\n";
