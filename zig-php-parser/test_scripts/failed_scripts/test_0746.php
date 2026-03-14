<?php
// __clone测试 4

class Magic{i} {
    public $count = 0;
    public function __clone() {
        $this->count = 1;
    }
}
$a = new Magic{i}();
$b = clone $a;
echo $b->count;
echo "
";
?>