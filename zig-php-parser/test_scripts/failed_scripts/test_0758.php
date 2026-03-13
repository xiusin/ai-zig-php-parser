<?php
// 命名空间测试 6
namespace Test\NS6;

class Helper {
    public static function id($x) { return $x; }
}
echo \Test\NS6\Helper::id(57);
echo "
";
?>