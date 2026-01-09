<?php
// Create a closure and call it immediately
$result = (function() { return 42; })();
echo "Result: " . $result . "\n";
?>
