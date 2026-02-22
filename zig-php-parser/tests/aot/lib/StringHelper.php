<?php
// lib/StringHelper.php
class StringHelper {
    public static function reverse(string $str): string {
        $result = "";
        for ($i = strlen($str) - 1; $i >= 0; $i--) {
            $result .= $str[$i];
        }
        return $result;
    }
    
    public static function uppercase(string $str): string {
        return strtoupper($str);
    }
}
