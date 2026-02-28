<?php

\$arr = ["a" => 1, "b" => 2];
\$keys = array_keys(\$arr);
\$vals = array_values(\$arr);
echo implode(",", \$keys) . "|" . implode(",", \$vals);

?>
