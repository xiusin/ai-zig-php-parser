<?php
function capitalizeFirst(string $str): string {
    return ucfirst($str);
}

function capitalizeWords2(string $str): string {
    return ucwords($str);
}

function uncapitalizeFirst(string $str): string {
    return lcfirst($str);
}

function kebabToSnake(string $str): string {
    return strtolower(preg_replace('/-/', '_', $str));
}

function snakeToKebab(string $str): string {
    return strtolower(preg_replace('/_/', '-', $str));
}

function humanize(string $str): string {
    return ucfirst(strtolower(str_replace(['_', '-'], ' ', $str)));
}

echo capitalizeFirst('hello') . "\n";
echo capitalizeWords2('hello world php') . "\n";
echo uncapitalizeFirst('Hello') . "\n";
echo kebabToSnake('hello-world') . "\n";
echo snakeToKebab('hello_world') . "\n";
echo humanize('hello_world_foo') . "\n";
echo "OK\n";
