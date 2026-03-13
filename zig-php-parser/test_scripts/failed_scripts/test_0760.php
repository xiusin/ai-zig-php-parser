<?php
// 命名空间测试 8
namespace Test\NS8;

class Helper {
    public static function id($x) { return $x; }
}
echo \Test\NS8\Helper::id(64);
echo "
";
?>