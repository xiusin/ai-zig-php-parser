<?php
function slugify(string $text): string {
    $text = strtolower($text);
    $text = preg_replace('/[^a-z0-9]+/i', '-', $text);
    $text = trim($text, '-');
    return preg_replace('/-+/', '-', $text);
}

function camelToSnake(string $input): string {
    return strtolower(preg_replace('/([a-z])([A-Z])/', '$1_$2', $input));
}

function snakeToCamel(string $input, bool $capitalizeFirst = false): string {
    $result = preg_replace('/_([a-z])/', fn($m) => strtoupper($m[1]), $input);
    if ($capitalizeFirst) {
        $result = ucfirst($result);
    }
    return $result;
}

function capitalizeWords(string $str): string {
    return ucwords(strtolower($str));
}

function removeWhitespace(string $str): string {
    return preg_replace('/\s+/', '', $str);
}

function reverseWords(string $str): string {
    return implode(' ', array_reverse(preg_split('/\s+/', $str)));
}

echo slugify("Hello World! This is a Test") . "\n";
echo camelToSnake("helloWorld") . "\n";
echo snakeToCamel("hello_world") . "\n";
echo capitalizeWords("HELLO world") . "\n";
echo removeWhitespace("Hello   World") . "\n";
echo reverseWords("Hello World PHP") . "\n";
echo "OK\n";
