<?php
// Store closure and call later
$getFive = function() { return 5; };
$x = $getFive;
echo "x(): " . $x() . "\n";
?>
