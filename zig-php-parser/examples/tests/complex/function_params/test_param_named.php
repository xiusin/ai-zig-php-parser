<?php
function createUser($name, $age, $city, $email) {
    return [
        "name" => $name,
        "age" => $age,
        "city" => $city,
        "email" => $email
    ];
}

$user = createUser(
    name: "Alice",
    age: 30,
    city: "NYC",
    email: "alice@example.com"
);

print_r($user);
