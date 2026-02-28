<?php

$x = 1;
$result = match($x) {
    1 => "one",
    2 => "two",
    default => "other",
};
echo $result;

?>
