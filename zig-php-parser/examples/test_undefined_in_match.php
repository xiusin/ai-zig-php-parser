<?php
// Test undefined variable in match expression
$result = match ($undefined_var) {
    1 => "one",
    2 => "two",
    default => "other"
};
echo "Done\n";
