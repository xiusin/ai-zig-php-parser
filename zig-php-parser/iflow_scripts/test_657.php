<?php
function isEven($n) { return $n % 2 == 0; } function filterEvens($arr) { return array_filter($arr, "isEven"); } echo implode(",", filterEvens(range(1,10)));?>
