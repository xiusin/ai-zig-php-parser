<?php
interface Printable {
    public function print();
}

class Document implements Printable {
    public function print() {
        echo "Document\n";
    }
}

class Image {
    public function display() {
        echo "Image\n";
    }
}

function printIfPrintable($obj) {
    if ($obj instanceof Printable) {
        $obj->print();
    } else {
        echo "Not printable\n";
    }
}

printIfPrintable(new Document());
printIfPrintable(new Image());
