<?php
class StringUtils {
    public static function camelCase(string $str): string {
        return lcfirst(str_replace(' ', '', ucwords(str_replace(['-', '_'], ' ', $str))));
    }

    public static function snakeCase(string $str): string {
        return strtolower(preg_replace('/(?<!^)[A-Z]/', '_$0', $str));
    }

    public static function kebabCase(string $str): string {
        return strtolower(preg_replace('/(?<!^)[A-Z]/', '-$0', $str));
    }

    public static function capitalize(string $str): string {
        return ucfirst(strtolower($str));
    }

    public static function reverse(string $str): string {
        return strrev($str);
    }

    public static function truncate(string $str, int $length, string $suffix = '...'): string {
        if (strlen($str) <= $length) return $str;
        return substr($str, 0, $length - strlen($suffix)) . $suffix;
    }
}

echo StringUtils::camelCase('hello_world') . "\n";
echo StringUtils::snakeCase('helloWorld') . "\n";
echo StringUtils::kebabCase('helloWorld') . "\n";
echo StringUtils::capitalize('HELLO world') . "\n";
echo StringUtils::reverse('PHP') . "\n";
echo StringUtils::truncate('Hello World Example Text', 15) . "\n";
echo "OK\n";
