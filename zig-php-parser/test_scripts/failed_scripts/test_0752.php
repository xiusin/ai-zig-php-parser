<?php
// 命名空间测试 0
namespace Test\NS0;

class Helper {
    public static function id($x) { return $x; }
}
echo \Test\NS0\Helper::id(5);
echo "
";
?>