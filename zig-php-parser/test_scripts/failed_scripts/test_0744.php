<?php
// __call测试 2

class Magic{i} {
    public function __call($name, $args) {
        return $name . ":" . count($args);
    }
}
$obj = new Magic{i}();
echo $obj->doSomething(1, 2, 3);
echo "
";
?>