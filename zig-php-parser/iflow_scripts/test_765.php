<?php
$x = match("b") { "a" => "A", "b" => "B", default => "C", }; echo $x;?>
