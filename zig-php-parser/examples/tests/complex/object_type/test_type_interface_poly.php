<?php
interface Storage {
    public function save($data);
    public function load();
}

class FileStorage implements Storage {
    private $file = "/tmp/data.txt";

    public function save($data) {
        file_put_contents($this->file, $data);
    }

    public function load() {
        return file_get_contents($this->file);
    }
}

class MemoryStorage implements Storage {
    private $data = "";

    public function save($data) {
        $this->data = $data;
    }

    public function load() {
        return $this->data;
    }
}

function useStorage(Storage $storage) {
    $storage->save("Hello World");
    echo "Loaded: " . $storage->load() . "\n";
}

useStorage(new FileStorage());
useStorage(new MemoryStorage());
