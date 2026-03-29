<?php
function trim2(string $str, string $characters = " \n\r\t\v\0"): string {
    return trim($str, $characters);
}

function ltrim2(string $str, string $characters = " \n\r\t\v\0"): string {
    return ltrim($str, $characters);
}

function rtrim2(string $str, string $characters = " \n\r\t\v\0"): string {
    return rtrim($str, $characters);
}

function stripWhitespace(string $str): string {
    return preg_replace('/\s+/', ' ', $str);
}

function addSlashes2(string $str): string {
    return addslashes($str);
}

function stripslashes2(string $str): string {
    return stripslashes($str);
}

$str = "  \t\n  Hello World  \n\t  ";
echo strlen(trim2($str)) . "\n";
echo ltrim2($str) === "Hello World  \n\t  " ? 'true' : 'false' . "\n";
echo stripWhitespace("Hello   World\n\nPHP") . "\n";
echo addSlashes2("Hello 'World'") . "\n";
echo stripslashes2(addslashes2("Hello 'World'")) . "\n";
echo "OK\n";
