<?php
class Data {
    public $value = 0;
}

function modify(&$obj) {
    $obj->value = 100;
}

$data = new Data();
modify($data);
echo "Value: " . $data->value . "\n";
