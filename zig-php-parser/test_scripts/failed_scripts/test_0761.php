<?php
// 命名空间测试 9
namespace Test\NS9;

class Helper {
    public static function id($x) { return $x; }
}
echo \Test\NS9\Helper::id(43);
echo "
";
?>