<?php
function greet($name) {
    return "Hello, " . $name;
}

function shout($message) {
    return $message . "!";
}

$greeting = greet("World");
$result = shout($greeting);
echo $result;
