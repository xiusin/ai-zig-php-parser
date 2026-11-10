<?php
class P { public $exists = 1; }
function byref(&$x) { $x = 55; }
$p = new P;
byref($p->undef);
var_dump($p);
