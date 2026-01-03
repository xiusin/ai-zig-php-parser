<?php
$user = "Admin";
$id = 123;

// Simple interpolation
echo "User: $user\n";

// Braced interpolation
echo "UserID: {$id}\n";

// Mixed types
echo "Info: {$user} has ID {$id}!\n";

// Nested in expression
$message = "Welcome {$user}";
echo $message . " to the system.\n";

// Empty strings and escaping (simple)
echo "Empty: " . "" . "End\n";
?>

