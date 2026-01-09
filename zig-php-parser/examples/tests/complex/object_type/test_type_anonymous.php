<?php
$object = new class {};

echo "Anonymous class: " . get_class($object) . "\n";
echo "Is object: " . (is_object($object) ? "true" : "false") . "\n";
