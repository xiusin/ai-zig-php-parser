<?php
class MyException extends Exception {}

echo "Test 4: Try-catch-finally\n";
try {
    throw new MyException("Error in try");
} catch (MyException $e) {
    echo "Caught in catch\n";
} finally {
    echo "Executed finally\n";
}

echo "done\n";
