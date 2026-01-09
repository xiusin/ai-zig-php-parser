<?php
class Channel {
    private $queue = array();
    
    public function send($value) {
        $this->queue[] = $value;
    }
    
    public function receive() {
        return array_shift($this->queue);
    }
    
    public function isEmpty() {
        return empty($this->queue);
    }
}

$channel = new Channel();

$channel->send("message1");
$channel->send("message2");
$channel->send("message3");

while (!$channel->isEmpty()) {
    echo "Received: " . $channel->receive() . "\n";
}
?>