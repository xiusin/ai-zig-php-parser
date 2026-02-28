<?php

class Builder {
    public \$value = "";
    public function add(\$s) {
        \$this->value .= \$s;
        return \$this;
    }
}
\$b = new Builder();
echo \$b->add("Hello")->add("World")->value;

?>
