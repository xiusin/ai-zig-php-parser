<?php
\$x = 1; echo match(\$x) { 1 => "one", 2 => "two", default => "other" };
?>
