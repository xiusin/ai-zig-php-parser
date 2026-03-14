<?php
// 命名空间测试 1
namespace Test\NS1;

class Helper {
    public static function id($x) { return $x; }
}
echo \Test\NS1\Helper::id(44);
echo "
";
?>