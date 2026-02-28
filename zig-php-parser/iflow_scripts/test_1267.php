<?php
$arr = array(1, 2); foreach ($arr as &$v) { $v *= 2; } echo implode(",", $arr);?>
