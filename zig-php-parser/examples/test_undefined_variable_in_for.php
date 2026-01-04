<?php
// Test undefined variable in for loop
for ($i = 0; $i < $undefined_limit; $i++) {
    echo $i . "\n";
}
echo "Done\n";
