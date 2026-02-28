<?php
$x = match(true) { $x > 10 => "big", default => "small", }; $x = 15; echo $x > 10 ? "big" : "small";?>
