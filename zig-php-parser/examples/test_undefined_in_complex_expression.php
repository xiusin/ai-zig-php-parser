<?php
// Test undefined variable in complex expression
$result = (($undefined_var + 10) * 2) / ($undefined_var - 5) + ($undefined_var & 15);
echo "Done\n";
