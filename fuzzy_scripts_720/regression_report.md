# fuzzy_scripts_720/pass/ 回归测试报告

测试时间: 2026-08-26 22:42:59
AOT 编译器: /Users/wangjianjun/products/parser/zig-out/bin/php-interpreter

## 统计

| 类别 | 数量 |
|------|------|
| Total | 108 |
| Pass | 69 |
| Fail (Compile) | 0
0 |
| Fail (Runtime) | 15 |
| Fail (Diff) | 21 |
| Skip | 3 |

## 失败明细

| 脚本 | 类型 | 详情 |
|------|------|------|
| f004_oop_deep_inheritance_magic.php | SKIP | PHP_error_exit=255 |
| f006_oop_observer_event_dispatcher.php | FAIL_DIFF | PHP:=== f006: Observer + Event Dispatcher + Priority + Exception Isolation ===|--- Event: user.login (normal) ---|[SECURITY] Checking IP: 192.168.1.1| |
| f007_string_encoding_crypto_hash.php | FAIL_RUNTIME | exit=142|kebabCase('HelloWorldFooBar'): hello-world-foo-bar truncate('Hello World', 8): Hello... pad('42', 5, '0', STR_PAD_LEFT): 00042 pad('42', 5, ' |
| f009_oop_decorator_chain_command.php | FAIL_DIFF | PHP:=== f009: Decorator Chain + Command Pattern + Middleware ===|After create: created=true|After update: value=new_value||AOT:=== f009: Decorator Cha |
| f012_json_tree_recursive_traverse.php | FAIL_DIFF | PHP:=== f012: JSON Tree + Recursive Traverse + Path Find ===|Tree structure:|root ({"type":"dir"})||AOT:=== f012: JSON Tree + Recursive Traverse + Pat |
| f025_coding_hamming_rle_lzw_crc.php | FAIL_RUNTIME | exit=142|=== f025: Hamming + RLE + LZW + CRC === --- Hamming (Repetition Code) --- Original: 'Hi' (2 bytes) Encoded: 000111000000111000000000000111111 |
| f028_dp_knapsack_lcs_lis.php | FAIL_RUNTIME | exit=142|--- 0/1 Knapsack --- Weights: 2,3,4,5 Values: 3,4,5,6 Cap: 8 Max value: 10, Items: 1,3  --- LCS ---  |
| f031_builder_fluent_immutable.php | FAIL_DIFF | PHP:=== f031: Builder + Fluent + Immutable + Freeze ===|POST https://api.example.com/v1/users?page=1&limit=20 [timeout=15s ssl=false]|Headers: {"Conte |
| f033_state_pattern_order_machine.php | FAIL_DIFF | PHP:=== f033: State Pattern + Order State Machine ===|Initial: pending|--- Paid (amount=100) ---||AOT:=== f033: State Pattern + Order State Machine == |
| f037_adapter_unified_cache.php | FAIL_RUNTIME | exit=255| Fatal error: Uncaught RuntimeException: Unknown cache:  in /Users/wangjianjun/products/parser/fuzzy_scripts_720/pass/f037_adapter_unified_ca |
| f038_composite_filesystem_tree.php | FAIL_RUNTIME | exit=142|Total size: 5120B Total leaves: 1 Max depth: 3  --- Find ---  |
| f044_json_deepops_merge_diff.php | FAIL_DIFF | PHP:=== f044: JSON Deep Ops + Merge + Diff + Schema ===|deepGet(user.name): Alice|deepGet(user.roles.0): admin||AOT:=== f044: JSON Deep Ops + Merge +  |
| f045_datetime_calendar_format.php | FAIL_DIFF | PHP:=== f045: DateTime + Calendar + Interval + Format ===|isLeapYear(2000): true|isLeapYear(1900): false||AOT:=== f045: DateTime + Calendar + Interval |
| f051_validator_rule_chain_batch.php | FAIL_DIFF | PHP:=== f051: Validator + Rule Chain + Batch ===|--- Form Validation ---|Valid: false||AOT:=== f051: Validator + Rule Chain + Batch ===|--- Form Valid |
| f061_graph_dijkstra_bellmanford_floyd.php | FAIL_DIFF | PHP:=== f061: Graph + Dijkstra + BellmanFord + FloydWarshall ===|--- Dijkstra from A ---|A→A = 0||AOT:=== f061: Graph + Dijkstra + BellmanFord + Flo |
| f065_crypto_rc4_sha1_base64_crc.php | FAIL_DIFF | PHP:=== f065: Crypto + RC4 + Base64 + CRC32 + SHA1 ===|--- RC4 ---|Plaintext: Hello World!||AOT:=== f065: Crypto + RC4 + Base64 + CRC32 + SHA1 ===|--- |
| f067_debug_char4.php | SKIP | PHP_error_exit=255 |
| f067_debug_char5.php | SKIP | PHP_error_exit=255 |
| f067_debug_full_parser.php | FAIL_RUNTIME | exit=255| Fatal error: Uncaught RuntimeException: Expected '"' at pos 38 char=8 in /Users/wangjianjun/products/parser/fuzzy_scripts_720/pass/f067_debu |
| f067_debug_single.php | FAIL_RUNTIME | exit=255| Fatal error: Uncaught RuntimeException: Expected end '"' in /Users/wangjianjun/products/parser/fuzzy_scripts_720/pass/f067_debug_single.php: |
| f067_json_parser_schema_path_diff.php | FAIL_RUNTIME | exit=255| Fatal error: Uncaught RuntimeException: Expected '"' in /Users/wangjianjun/products/parser/fuzzy_scripts_720/pass/f067_json_parser_schema_pa |
| f070_event_sourcing_cqrs_snapshot.php | FAIL_DIFF | PHP:=== f070: Event Sourcing + Snapshot + CQRS ===|--- Event Sourcing: Bank Account ---|Initial balances: acc1=0 acc2=0||AOT:=== f070: Event Sourcing  |
| f072_type_inference_hindley_milner.php | FAIL_DIFF | PHP:=== f072: Type Inference + Hindley-Milner ===|--- Literal Inference ---|42 → int||AOT:=== f072: Type Inference + Hindley-Milner ===|--- Literal  |
| f080_db_transaction_mvcc_deadlock.php | FAIL_DIFF | PHP:=== f080: DB Transaction + Isolation + MVCC + Deadlock ===|--- Basic Transaction ---|Read user:1: {"name":"Alice","balance":100}||AOT:=== f080: DB |
| f085_geo_rtree_knn_geocoder.php | FAIL_RUNTIME | exit=255| Fatal error: Uncaught TypeError: BoundingBox::contains(): Argument #1 ($p) must be of type Point, null given in /Users/wangjianjun/products/ |
| f087_rbac_abac_policy_inheritance.php | FAIL_DIFF | PHP:=== f087: RBAC + ABAC + Policy + Inheritance ===|--- RBAC ---|Alice can article:write = true||AOT:=== f087: RBAC + ABAC + Policy + Inheritance === |
| f095_compiler_opt_constfold_dce_cse.php | FAIL_RUNTIME | exit=142|  c3 = const(10)   t4 = const(7)   ret   --- Dead Code Elimination ---  |
| f097_search_engine_inverted_index_tfidf.php | FAIL_RUNTIME | exit=255| Fatal error: Uncaught DivisionByZeroError: Division by zero in /Users/wangjianjun/products/parser/fuzzy_scripts_720/pass/f097_search_engine_ |
| f105_db_index_btree_hash_queryplan.php | FAIL_DIFF | PHP:=== f105: DB Index + BTree + HashIndex + QueryPlan ===|--- B-Tree Index ---|Inserted: 10, 20, 5, 6, 12, 30, 7, 17, 25, 31, 3, 1, 40, 50, 15, 8, 45 |
| f113_distributed_consistenthash_vectorclock_quorum.php | FAIL_RUNTIME | exit=133|--- Consistent Hashing --- Distribution (1000 keys):   node3: 302 ##############################   node1: 438 ############################### |
| f117_search_engine_inverted_tfidf_bm25.php | FAIL_DIFF | PHP:=== f117: Search Engine + InvertedIndex + TF-IDF + BM25 ===|--- Build Index ---|Index stats: {"documents":7,"terms":20,"avg_doc_length":5.7}||AOT: |
| f124_container_orchestrator_pod_service_autoscale.php | FAIL_DIFF | PHP:=== f124: Container Orchestrator + Pod + ServiceDiscovery + Autoscale ===|--- Setup Cluster ---|Nodes: 3||AOT:=== f124: Container Orchestrator + P |
| f134_event_sourcing_snapshot_cqrs_projection.php | FAIL_DIFF | PHP:=== f134: EventSourcing + Snapshot + CQRS + Projection ===|--- Event Sourcing: Order Lifecycle ---|Order state:||AOT:=== f134: EventSourcing + Sna |
| f135_math_number_theory_crt_miller_rabin.php | FAIL_RUNTIME | exit=133|--- Primality Testing --- Deterministic: ✓✓✓✓✓✓✓✓✓✓ primes ✓✓✓✓✓✓✓✓✓✓ composites Miller-Rabin (large  |
| f151_type_system_generics_variance.php | FAIL_DIFF | PHP:=== f151: Type System + Generics + Variance + Inference ===|--- Covariant Return ---|Dog shelter: Woof||AOT:=== f151: Type System + Generics + Var |
| f160_virtual_fs_path_traversal.php | FAIL_DIFF | PHP:=== f160: Virtual FS + Path Ops + Directory Traversal ===|--- Virtual File System ---|Directory structure:||AOT:=== f160: Virtual FS + Path Ops +  |
| f161_json_xml_csv_parsing.php | FAIL_RUNTIME | exit=1|  Team A,95   Team B,87    --- XML Parsing --- error: RuntimeError  |
| f163_event_driven_dispatch_bus.php | FAIL_DIFF | PHP:=== f163: Event-Driven + PubSub + EventSourcing ===|--- Event Bus Pub/Sub ---|[Email Service] Welcome email sent to Alice||AOT:=== f163: Event-Dri |
| f178_numeric_precision_matrix.php | FAIL_RUNTIME | exit=142|   A - B:   [   -8.00,    -6.00,    -4.00]   [   -2.00,     0.00,     2.00]   [    4.00,     6.00,     8.00]  |
