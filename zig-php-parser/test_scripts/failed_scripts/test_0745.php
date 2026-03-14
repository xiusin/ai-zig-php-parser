<?php
// __invoke测试 3

class Magic{i} {
    public function __invoke($x) {
        return $x * 2;
    }
}
$obj = new Magic{i}();
echo $obj(5);
echo "
";
?>