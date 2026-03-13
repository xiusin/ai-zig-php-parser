<?php
// __get/__set测试 6

class Magic{i} {
    private $data = [];
    public function __get($key) { return $this->data[$key] ?? "none"; }
    public function __set($key, $val) { $this->data[$key] = $val; }
}
$obj = new Magic{i}();
$obj->test = "value";
echo $obj->test;
echo "
";
?>