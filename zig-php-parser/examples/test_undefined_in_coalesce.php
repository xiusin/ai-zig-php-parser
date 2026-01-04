<?php
// Test undefined variable in null coalesce operator
$result = $undefined_var ?? "default";
echo "Done\n";
