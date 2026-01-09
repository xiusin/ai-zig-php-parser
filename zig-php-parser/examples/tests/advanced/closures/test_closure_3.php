<?php
class EventManager {
    private $handlers = array();
    
    public function on($event, $handler) {
        $this->handlers[$event] = $handler;
    }
    
    public function trigger($event, $data) {
        if (isset($this->handlers[$event])) {
            return $this->handlers[$event]($data);
        }
        return null;
    }
}

$events = new EventManager();

$events->on("user.created", function($user) {
    return "User created: " . $user["name"];
});

$events->on("user.updated", function($user) {
    return "User updated: " . $user["name"];
});

echo $events->trigger("user.created", array("name" => "Alice")) . "\n";
echo $events->trigger("user.updated", array("name" => "Bob")) . "\n";
?>