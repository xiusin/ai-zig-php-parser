<?php
// 命名空间测试 7
namespace Test\NS7;

class Helper {
    public static function id($x) { return $x; }
}
echo \Test\NS7\Helper::id(66);
echo "
";
?>