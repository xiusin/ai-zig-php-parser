<?php
function parseTemplate(string $template, array $data): string {
    $result = preg_replace_callback('/\{\{(\w+)\}\}/', function($matches) use ($data) {
        return $data[$matches[1]] ?? '';
    }, $template);

    $result = preg_replace_callback('/\{% (\w+) %\}/', function($matches) use ($data) {
        return '<!-- ' . ($data[$matches[1]] ?? '') . ' -->';
    }, $result);

    return $result;
}

$template = "Hello {{name}}, you have {{count}} messages. {% comment %}";
$data = ['name' => 'Alice', 'count' => 5, 'comment' => 'Test comment'];
echo parseTemplate($template, $data) . "\n";

$template2 = "User: {{user}}, Email: {{email}}, Status: {{status}}";
$data2 = ['user' => 'Bob', 'email' => 'bob@example.com'];
echo parseTemplate($template2, $data2) . "\n";
echo "OK\n";
