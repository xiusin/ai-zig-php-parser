<?php
$arr = array(); for ($i = 1; $i <= 50; $i++) { if ($i % 5 == 0 && $i % 7 == 0) $arr[] = $i; } echo implode(",", $arr);?>
