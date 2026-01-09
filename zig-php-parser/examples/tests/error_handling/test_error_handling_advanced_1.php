<?php
function handleErrors($e) {
    echo "Caught: " . get_class($e) . "\n";
    echo "Message: " . $e->getMessage() . "\n";
    echo "File: " . $e->getFile() . "\n";
    echo "Line: " . $e->getLine() . "\n";
}

try {
    throw new Error("This is an Error");
} catch (Throwable $e) {
    handleErrors($e);
}

echo "\n";

try {
    throw new Exception("This is an Exception");
} catch (Throwable $e) {
    handleErrors($e);
}
?>