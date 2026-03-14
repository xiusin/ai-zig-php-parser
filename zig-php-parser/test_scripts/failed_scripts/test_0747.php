<?php
// __toString测试 5

class Magic{i} {
    public function __toString() {
        return "magic{i}";
    }
}
$obj = new Magic{i}();
echo (string)$obj;
echo "
";
?>