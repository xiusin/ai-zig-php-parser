<?php
// 命名空间测试 4
namespace Test\NS4;

class Helper {
    public static function id($x) { return $x; }
}
echo \Test\NS4\Helper::id(42);
echo "
";
?>