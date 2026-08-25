# fuzzy_scripts_720/pass/ 回归测试报告

测试时间: 2026-08-25 12:15:14
AOT 编译器: /Users/wangjianjun/products/parser/zig-out/bin/php-interpreter

## 统计

| 类别 | 数量 |
|------|------|
| Total | 108 |
| Pass | 49 |
| Fail (Compile) | 0
0 |
| Fail (Runtime) | 20 |
| Fail (Diff) | 35 |
| Skip | 4 |

## 失败明细

| 脚本 | 类型 | 详情 |
|------|------|------|
| f004_oop_deep_inheritance_magic.php | SKIP | PHP_error_exit=255 |
| f006_oop_observer_event_dispatcher.php | FAIL_DIFF | PHP:=== f006: Observer + Event Dispatcher + Priority + Exception Isolation ===|--- Event: user.login (normal) ---|[SECURITY] Checking IP: 192.168.1.1| |
| f007_string_encoding_crypto_hash.php | FAIL_RUNTIME | exit=142|kebabCase('HelloWorldFooBar'): hello-world-foo-bar truncate('Hello World', 8): Hello... pad('42', 5, '0', STR_PAD_LEFT): 00042 pad('42', 5, ' |
| f009_oop_decorator_chain_command.php | FAIL_DIFF | PHP:=== f009: Decorator Chain + Command Pattern + Middleware ===|After create: created=true|After update: value=new_value||AOT:=== f009: Decorator Cha |
| f010_oop_singleton_registry_di.php | FAIL_RUNTIME | exit=255| Fatal error: Uncaught RuntimeException: Cannot resolve: UserService in /Users/wangjianjun/products/parser/fuzzy_scripts_720/pass/f010_oop_si |
| f012_json_tree_recursive_traverse.php | FAIL_DIFF | PHP:=== f012: JSON Tree + Recursive Traverse + Path Find ===|Tree structure:|root ({"type":"dir"})||AOT:=== f012: JSON Tree + Recursive Traverse + Pat |
| f024_rbac_role_inheritance_policy.php | FAIL_DIFF | PHP:=== f024: RBAC + Role Inheritance + Policy ===|--- Permission Matrix ---|read    write   edit    delete||AOT:=== f024: RBAC + Role Inheritance + P |
| f025_coding_hamming_rle_lzw_crc.php | FAIL_RUNTIME | exit=142|=== f025: Hamming + RLE + LZW + CRC === --- Hamming (Repetition Code) --- Original: 'Hi' (2 bytes) Encoded: 000111000000111000000000000111111 |
| f026_linkedlist_stack_queue_deque.php | FAIL_DIFF | PHP:=== f026: LinkedList + Stack + Queue + Deque + RingBuffer ===|--- LinkedList ---|List: 1 -> 2 -> 3 -> 4 -> 5||AOT:=== f026: LinkedList + Stack + Q |
| f028_dp_knapsack_lcs_lis.php | FAIL_RUNTIME | exit=142|--- 0/1 Knapsack --- Weights: 2,3,4,5 Values: 3,4,5,6 Cap: 8 Max value: 10, Items: 1,3  --- LCS ---  |
| f031_builder_fluent_immutable.php | FAIL_DIFF | PHP:=== f031: Builder + Fluent + Immutable + Freeze ===|POST https://api.example.com/v1/users?page=1&limit=20 [timeout=15s ssl=false]|Headers: {"Conte |
| f032_chain_responsibility_middleware.php | FAIL_DIFF | PHP:=== f032: Chain of Responsibility + Middleware Pipeline ===|--- Test 1: Normal request ---|{"token":"abc123","ip":"192.168.1.1","url":"\/api\/user |
| f033_state_pattern_order_machine.php | FAIL_DIFF | PHP:=== f033: State Pattern + Order State Machine ===|Initial: pending|--- Paid (amount=100) ---||AOT:=== f033: State Pattern + Order State Machine == |
| f034_template_method_pipeline.php | FAIL_DIFF | PHP:=== f034: Template Method + Algorithm Skeleton + Hooks ===|--- JSON Processor ---|{"result":{"id":"123","name":"ALICE","extra":"data","processed_a |
| f036_strategy_dynamic_pricing.php | FAIL_DIFF | PHP:=== f036: Strategy + Dynamic Switch + Closure Strategies ===|--- Regular ---|Widget: $10 × 5 = $50.00||AOT:=== f036: Strategy + Dynamic Switch +  |
| f037_adapter_unified_cache.php | FAIL_RUNTIME | exit=255| Fatal error: Uncaught RuntimeException: Unknown cache:  in /Users/wangjianjun/products/parser/fuzzy_scripts_720/pass/f037_adapter_unified_ca |
| f038_composite_filesystem_tree.php | FAIL_RUNTIME | exit=142|Total size: 5120B Total leaves: 1 Max depth: 3  --- Find ---  |
| f044_json_deepops_merge_diff.php | FAIL_RUNTIME | exit=255| Fatal error: Uncaught TypeError: JsonTools::deepMerge(): Argument #1 ($base) must be of type array, null given in /Users/wangjianjun/product |
| f045_datetime_calendar_format.php | FAIL_DIFF | PHP:=== f045: DateTime + Calendar + Interval + Format ===|isLeapYear(2000): true|isLeapYear(1900): false||AOT:=== f045: DateTime + Calendar + Interval |
| f051_validator_rule_chain_batch.php | FAIL_DIFF | PHP:=== f051: Validator + Rule Chain + Batch ===|--- Form Validation ---|Valid: false||AOT:=== f051: Validator + Rule Chain + Batch ===|--- Form Valid |
| f056_crdt_gcounter_lww_orset.php | FAIL_DIFF | PHP:=== f056: CRDT + GCounter + LWW + ORSet ===|--- G-Counter ---|nodeA: 5 counts={"nodeA":5}||AOT:=== f056: CRDT + GCounter + LWW + ORSet ===|--- G-C |
| f057_workflow_engine_rollback.php | FAIL_DIFF | PHP:=== f057: Workflow Engine + Transitions + Rollback ===|--- Run 1: Success Path ---|Visited: start → fetch → validate → process → notify � |
| f061_graph_dijkstra_bellmanford_floyd.php | FAIL_DIFF | PHP:=== f061: Graph + Dijkstra + BellmanFord + FloydWarshall ===|--- Dijkstra from A ---|A→A = 0||AOT:=== f061: Graph + Dijkstra + BellmanFord + Flo |
| f065_crypto_rc4_sha1_base64_crc.php | FAIL_DIFF | PHP:=== f065: Crypto + RC4 + Base64 + CRC32 + SHA1 ===|--- RC4 ---|Plaintext: Hello World!||AOT:=== f065: Crypto + RC4 + Base64 + CRC32 + SHA1 ===|--- |
| f067_debug_char4.php | SKIP | PHP_error_exit=255 |
| f067_debug_char5.php | SKIP | PHP_error_exit=255 |
| f067_debug_full_parser.php | FAIL_RUNTIME | exit=255| Fatal error: Uncaught RuntimeException: Expected '"' at pos 38 char=8 in /Users/wangjianjun/products/parser/fuzzy_scripts_720/pass/f067_debu |
| f067_debug_single.php | FAIL_RUNTIME | exit=255| Fatal error: Uncaught RuntimeException: Expected end '"' in /Users/wangjianjun/products/parser/fuzzy_scripts_720/pass/f067_debug_single.php: |
| f067_json_parser_schema_path_diff.php | FAIL_RUNTIME | exit=255| Fatal error: Uncaught RuntimeException: Expected '"' in /Users/wangjianjun/products/parser/fuzzy_scripts_720/pass/f067_json_parser_schema_pa |
| f067_min_repro.php | SKIP | PHP_error_exit=255 |
| f070_event_sourcing_cqrs_snapshot.php | FAIL_RUNTIME | exit=255| Fatal error: Uncaught TypeError: Cannot assign null to property BankAccount::$state of type array in /Users/wangjianjun/products/parser/fuzz |
| f072_type_inference_hindley_milner.php | FAIL_DIFF | PHP:=== f072: Type Inference + Hindley-Milner ===|--- Literal Inference ---|42 → int||AOT:=== f072: Type Inference + Hindley-Milner ===|--- Literal  |
| f080_db_transaction_mvcc_deadlock.php | FAIL_DIFF | PHP:=== f080: DB Transaction + Isolation + MVCC + Deadlock ===|--- Basic Transaction ---|Read user:1: {"name":"Alice","balance":100}||AOT:=== f080: DB |
| f085_geo_rtree_knn_geocoder.php | FAIL_RUNTIME | exit=255| Fatal error: Uncaught TypeError: BoundingBox::contains(): Argument #1 ($p) must be of type Point, null given in /Users/wangjianjun/products/ |
| f087_rbac_abac_policy_inheritance.php | FAIL_DIFF | PHP:=== f087: RBAC + ABAC + Policy + Inheritance ===|--- RBAC ---|Alice can article:write = true||AOT:=== f087: RBAC + ABAC + Policy + Inheritance === |
| f090_promise_future_async_concurrent.php | FAIL_DIFF | PHP:=== f090: Promise + Future + Async + Concurrent ===|--- Basic Promise ---|Chained: 43||AOT:=== f090: Promise + Future + Async + Concurrent ===|--- |
| f095_compiler_opt_constfold_dce_cse.php | FAIL_RUNTIME | exit=142|  c3 = const(10)   t4 = const(7)   ret   --- Dead Code Elimination ---  |
| f097_search_engine_inverted_index_tfidf.php | FAIL_RUNTIME | exit=255| Fatal error: Uncaught DivisionByZeroError: Division by zero in /Users/wangjianjun/products/parser/fuzzy_scripts_720/pass/f097_search_engine_ |
| f102_memory_gc_marksweep_refcount_gen.php | FAIL_DIFF | PHP:=== f102: Memory Mgmt + MarkSweep + RefCount + Generational ===|--- Mark-Sweep GC ---|Heap: 5 objects, 544 bytes||AOT:=== f102: Memory Mgmt + Mark |
| f104_game_engine_ecs_collision_render.php | FAIL_DIFF | PHP:=== f104: Game Engine + ECS + Collision + Render ===|--- Setup Game World ---|Entities: 4||AOT:=== f104: Game Engine + ECS + Collision + Render == |
| f105_db_index_btree_hash_queryplan.php | FAIL_DIFF | PHP:=== f105: DB Index + BTree + HashIndex + QueryPlan ===|--- B-Tree Index ---|Inserted: 10, 20, 5, 6, 12, 30, 7, 17, 25, 31, 3, 1, 40, 50, 15, 8, 45 |
| f110_os_sim_process_memory_filesystem.php | FAIL_DIFF | PHP:=== f110: OS Sim + Process + Memory + FileSystem ===|--- CPU Scheduling ---|FCFS:||AOT:=== f110: OS Sim + Process + Memory + FileSystem ===|--- CP |
| f113_distributed_consistenthash_vectorclock_quorum.php | FAIL_RUNTIME | exit=133|--- Consistent Hashing --- Distribution (1000 keys):   node3: 302 ##############################   node1: 438 ############################### |
| f117_search_engine_inverted_tfidf_bm25.php | FAIL_DIFF | PHP:=== f117: Search Engine + InvertedIndex + TF-IDF + BM25 ===|--- Build Index ---|Index stats: {"documents":7,"terms":20,"avg_doc_length":5.7}||AOT: |
| f119_logging_structured_levels_rotation.php | FAIL_DIFF | PHP:=== f119: Logging + Structured + Levels + Rotation ===|--- Basic Logging ---|[info] app: User logged in {"user":"alice","ip":"192.168.1.1"}||AOT:= |
| f124_container_orchestrator_pod_service_autoscale.php | FAIL_DIFF | PHP:=== f124: Container Orchestrator + Pod + ServiceDiscovery + Autoscale ===|--- Setup Cluster ---|Nodes: 3||AOT:=== f124: Container Orchestrator + P |
| f134_event_sourcing_snapshot_cqrs_projection.php | FAIL_RUNTIME | exit=1|=== f134: EventSourcing + Snapshot + CQRS + Projection === --- Event Sourcing: Order Lifecycle --- error: InvalidArgument  |
| f135_math_number_theory_crt_miller_rabin.php | FAIL_RUNTIME | exit=133|--- Primality Testing --- Deterministic: ✓✓✓✓✓✓✓✓✓✓ primes ✓✓✓✓✓✓✓✓✓✓ composites Miller-Rabin (large  |
| f151_type_system_generics_variance.php | FAIL_DIFF | PHP:=== f151: Type System + Generics + Variance + Inference ===|--- Covariant Return ---|Dog shelter: Woof||AOT:=== f151: Type System + Generics + Var |
| f160_virtual_fs_path_traversal.php | FAIL_DIFF | PHP:=== f160: Virtual FS + Path Ops + Directory Traversal ===|--- Virtual File System ---|Directory structure:||AOT:=== f160: Virtual FS + Path Ops +  |
| f161_json_xml_csv_parsing.php | FAIL_RUNTIME | exit=1|  ,   ,    --- XML Parsing --- error: RuntimeError  |
| f163_event_driven_dispatch_bus.php | FAIL_DIFF | PHP:=== f163: Event-Driven + PubSub + EventSourcing ===|--- Event Bus Pub/Sub ---|[Email Service] Welcome email sent to Alice||AOT:=== f163: Event-Dri |
| f164_plugin_hook_system.php | FAIL_DIFF | PHP:=== f164: Plugin System + Hooks + Lifecycle ===|--- Register Plugins ---|Registered: seo, cache, analytics||AOT:=== f164: Plugin System + Hooks +  |
| f171_state_machine_dfa.php | FAIL_DIFF | PHP:=== f171: State Machine + DFA + NFA ===|--- Order State Machine ---|Initial: pending||AOT:=== f171: State Machine + DFA + NFA ===|--- Order State  |
| f175_decorator_strategy_template.php | FAIL_DIFF | PHP:=== f175: Decorator + Strategy + Template Method ===|--- Decorator: Logger Formatting ---|Base: [INFO] Hello||AOT:=== f175: Decorator + Strategy + |
| f176_specification_chain_rules.php | FAIL_DIFF | PHP:=== f176: Specification Pattern + Rule Chain ===|--- Specification: User Validation ---|User evaluation:||AOT:=== f176: Specification Pattern + Ru |
| f177_graph_traversal_dfs_bfs.php | FAIL_RUNTIME | exit=142|  Vertices: A, B, C, D, E, F, G   DFS from A: A → B → D → G → E → F → C   BFS from A: A → B → C → D → E → F → G  ---  |
| f178_numeric_precision_matrix.php | FAIL_RUNTIME | exit=142|   A - B:   [   -8.00,    -6.00,    -4.00]   [   -2.00,     0.00,     2.00]   [    4.00,     6.00,     8.00]  |
| f179_visitor_composite_ast.php | FAIL_DIFF | PHP:=== f179: Visitor + Composite + AST Walk ===|--- AST Construction ---|--- Print Visitor (AST Structure) ---||AOT:=== f179: Visitor + Composite + A |
