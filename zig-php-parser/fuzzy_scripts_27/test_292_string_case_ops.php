<?php
function strUpper2(string $str): string {
    return strtoupper($str);
}

function strLower2(string $str): string {
    return strtolower($str);
}

function strTitle(string $str): string {
    return ucwords(strtolower($str));
}

function strUpperFirst(string $str): string {
    return ucfirst($str);
}

function strLowerFirst(string $str): string {
    return lcfirst($str);
}

function strSwapCase(string $str): string {
    for ($i = 0; $i < strlen($str); $i++) {
        $str[$i] = ctype_upper($str[$i]) ? strtolower($str[$i]) : strtoupper($str[$i]);
    }
    return $str;
}

echo strUpper2('hello') . "\n";
echo strLower2('HELLO') . "\n";
echo strTitle('HELLO WORLD') . "\n";
echo strUpperFirst('hello') . "\n";
echo strLowerFirst('HELLO') . "\n";
echo strSwapCase('Hello World') . "\n";
echo "OK\n";
