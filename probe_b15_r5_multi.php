<?php
function multi(&$a, $b, &$c) { $a = 1; $c = 3; }
multi($u1, $u2, $u3);
var_dump($u1, $u2, $u3);
$str = 'hello';
parse_str($str, $out);
var_dump($out);
