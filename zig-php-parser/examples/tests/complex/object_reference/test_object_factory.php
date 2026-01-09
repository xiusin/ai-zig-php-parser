<?php
class User {
    public $id;
    public $name;
    public static $counter = 0;

    public function __construct($name) {
        $this->id = ++self::$counter;
        $this->name = $name;
    }
}

function createUser($name) {
    return new User($name);
}

$users = [];
for ($i = 0; $i < 5; $i++) {
    $users[] = createUser("User" . ($i + 1));
}

foreach ($users as $user) {
    echo "User {$user->id}: {$user->name}\n";
}
