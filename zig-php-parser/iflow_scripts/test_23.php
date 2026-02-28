<?php

$value = 2;
$result = match($value) {
    1 => "one",
    2 => "two",
    3 => "three",
    default => "other",
};
echo $result;

?>
