<?php
// 命名空间测试 2
namespace Test\NS2;

class Helper {
    public static function id($x) { return $x; }
}
echo \Test\NS2\Helper::id(36);
echo "
";
?>