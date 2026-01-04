<?php
// Test undefined variable in nested array
$arr = [
    "level1" => [
        "level2" => [
            $undefined_var
        ]
    ]
];
echo "Done\n";