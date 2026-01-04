<?php
// Test undefined property access
$obj = new stdClass();
$val = $obj->undefined_property;
echo "Done\n";
