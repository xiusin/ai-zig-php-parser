<?php

$a = true;
$b = false;
$c = true;
$result = ($a && $b) || ($b && $c) || ($a && $c);
echo $result ? "true" : "false";

?>
