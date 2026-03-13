<?php
// 命名空间测试 3
namespace Test\NS3;

class Helper {
    public static function id($x) { return $x; }
}
echo \Test\NS3\Helper::id(76);
echo "
";
?>