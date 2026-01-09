<?php
trait Loggable {
    public function log($msg) {
        echo $msg . "\n";
    }
}

class User {
    use Loggable;
}

class Product {
    use Loggable;
}

$user = new User();
$product = new Product();

$user->log("User logged in");
$product->log("Product viewed");
