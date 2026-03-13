<?php
// 命名空间测试 5
namespace Test\NS5;

class Helper {
    public static function id($x) { return $x; }
}
echo \Test\NS5\Helper::id(16);
echo "
";
?>