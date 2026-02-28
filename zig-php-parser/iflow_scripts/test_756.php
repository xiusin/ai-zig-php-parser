<?php
$arr = array(1, 2, 3, 4, 5); $first = array_slice($arr, 0, 2); $last = array_slice($arr, -2); echo implode(",", array_merge($first, $last));?>
