# fuzzy_scripts_720/pass/ 回归测试报告

测试时间: 2026-08-03 21:47:40
AOT 编译器: /Users/wangjianjun/products/parser/zig-out/bin/php-interpreter

## 统计

| 类别 | 数量 |
|------|------|
| Total | 67 |
| Pass | 25 |
| Fail (Compile) | 3 |
| Fail (Runtime) | 16 |
| Fail (Diff) | 22 |
| Skip | 1 |

## 失败明细

| 脚本 | 类型 | 详情 |
|------|------|------|
| f004_oop_deep_inheritance_magic.php | SKIP | PHP_error_exit=255 |
| f006_oop_observer_event_dispatcher.php | FAIL_DIFF | PHP:=== f006: Observer + Event Dispatcher + Priority + Exception Isolation ===|--- Event: user.login (normal) ---|[SECURITY] Checking IP: 192.168.1.1| |
| f007_string_encoding_crypto_hash.php | FAIL_DIFF | PHP:=== f007: String Ops + Hash + Crypto + Format ===|--- String Utils ---|reverse('hello'): olleh||AOT:=== f007: String Ops + Hash + Crypto + Format  |
| f009_oop_decorator_chain_command.php | FAIL_DIFF | PHP:=== f009: Decorator Chain + Command Pattern + Middleware ===|After create: created=true|After update: value=new_value||AOT:=== f009: Decorator Cha |
| f025_coding_hamming_rle_lzw_crc.php | FAIL_RUNTIME | exit=142|Verify wrong: false  --- LZW --- Original: 'abababababababababababababababab' (32 bytes) Compressed: [97,98,256,258,257,260,259,262,261,264]. |
| f027_number_theory_primes_modular.php | FAIL_COMPILE | Error: Compilation failed with 1 errors, 0 warnings [1mf027_number_theory_primes_modular.php[0m: [31merror[0m: Zig code generation failed: AstDire |
| f028_dp_knapsack_lcs_lis.php | FAIL_RUNTIME | exit=142 |
| f031_builder_fluent_immutable.php | FAIL_DIFF | PHP:=== f031: Builder + Fluent + Immutable + Freeze ===|POST https://api.example.com/v1/users?page=1&limit=20 [timeout=15s ssl=false]|Headers: {"Conte |
| f033_state_pattern_order_machine.php | FAIL_DIFF | PHP:=== f033: State Pattern + Order State Machine ===|Initial: pending|--- Paid (amount=100) ---||AOT:=== f033: State Pattern + Order State Machine == |
| f034_template_method_pipeline.php | FAIL_DIFF | PHP:=== f034: Template Method + Algorithm Skeleton + Hooks ===|--- JSON Processor ---|{"result":{"id":"123","name":"ALICE","extra":"data","processed_a |
| f037_adapter_unified_cache.php | FAIL_RUNTIME | exit=255| Fatal error: Uncaught RuntimeException: Unknown cache:  in /Users/wangjianjun/products/parser/fuzzy_scripts_720/pass/f037_adapter_unified_ca |
| f038_composite_filesystem_tree.php | FAIL_RUNTIME | exit=142|      📄 autoload.php (256B)       📄 composer.php (384B)   📄 README.md (128B)  Total size: 5120B  |
| f044_json_deepops_merge_diff.php | FAIL_DIFF | PHP:=== f044: JSON Deep Ops + Merge + Diff + Schema ===|deepGet(user.name): Alice|deepGet(user.roles.0): admin||AOT:=== f044: JSON Deep Ops + Merge +  |
| f051_validator_rule_chain_batch.php | FAIL_DIFF | PHP:=== f051: Validator + Rule Chain + Batch ===|--- Form Validation ---|Valid: false||AOT:=== f051: Validator + Rule Chain + Batch ===|--- Form Valid |
| f061_graph_dijkstra_bellmanford_floyd.php | FAIL_DIFF | PHP:=== f061: Graph + Dijkstra + BellmanFord + FloydWarshall ===|--- Dijkstra from A ---|A→A = 0||AOT:=== f061: Graph + Dijkstra + BellmanFord + Flo |
| f065_crypto_rc4_sha1_base64_crc.php | FAIL_DIFF | PHP:=== f065: Crypto + RC4 + Base64 + CRC32 + SHA1 ===|--- RC4 ---|Plaintext: Hello World!||AOT:=== f065: Crypto + RC4 + Base64 + CRC32 + SHA1 ===|--- |
| f066_hamming_code_parity_checksum.php | FAIL_COMPILE | Error: Compilation failed with 1 errors, 0 warnings [1mf066_hamming_code_parity_checksum.php[0m: [31merror[0m: Zig code generation failed: AstDire |
| f067_json_parser_schema_path_diff.php | FAIL_RUNTIME | exit=142| Warning: foreach() argument must be of type array|object, null given in /Users/wangjianjun/products/parser/fuzzy_scripts_720/pass/f067_json_ |
| f070_event_sourcing_cqrs_snapshot.php | FAIL_DIFF | PHP:=== f070: Event Sourcing + Snapshot + CQRS ===|--- Event Sourcing: Bank Account ---|Initial balances: acc1=0 acc2=0||AOT:=== f070: Event Sourcing  |
| f072_type_inference_hindley_milner.php | FAIL_DIFF | PHP:=== f072: Type Inference + Hindley-Milner ===|--- Literal Inference ---|42 → int||AOT:=== f072: Type Inference + Hindley-Milner ===|--- Literal  |
| f080_db_transaction_mvcc_deadlock.php | FAIL_DIFF | PHP:=== f080: DB Transaction + Isolation + MVCC + Deadlock ===|--- Basic Transaction ---|Read user:1: {"name":"Alice","balance":100}||AOT:=== f080: DB |
| f081_bplustree_index_range_query.php | FAIL_RUNTIME | exit=142|=== f081: B+Tree Index + Range Query + Pages === --- B+Tree Insert & Search ---  |
| f085_geo_rtree_knn_geocoder.php | FAIL_RUNTIME | exit=255| Fatal error: Uncaught TypeError: BoundingBox::contains(): Argument #1 ($p) must be of type Point, null given in /Users/wangjianjun/products/ |
| f087_rbac_abac_policy_inheritance.php | FAIL_RUNTIME | exit=142|Carol can article:read = false Carol can article:write = false Bob can comment:read (inherited) = false  --- ABAC ---  |
| f095_compiler_opt_constfold_dce_cse.php | FAIL_RUNTIME | exit=142|  c3 = const(10)   t4 = const(7)   ret t2  --- Dead Code Elimination ---  |
| f102_memory_gc_marksweep_refcount_gen.php | FAIL_RUNTIME | exit=142|--- Cycle Detection --- Cycle detection: 2 cycles found  --- Generational GC --- Total objects: 15  |
| f104_game_engine_ecs_collision_render.php | FAIL_RUNTIME | exit=142|  {"type":"moved","entity":3,"from":[400,175],"to":[396,174.5]}   {"type":"death","entity":2} Entities remaining: 3  --- Entity States ---  |
| f105_db_index_btree_hash_queryplan.php | FAIL_DIFF | PHP:=== f105: DB Index + BTree + HashIndex + QueryPlan ===|--- B-Tree Index ---|Inserted: 10, 20, 5, 6, 12, 30, 7, 17, 25, 31, 3, 1, 40, 50, 15, 8, 45 |
| f113_distributed_consistenthash_vectorclock_quorum.php | FAIL_RUNTIME | exit=133|--- Consistent Hashing --- Distribution (1000 keys):   node3: 302 ##############################   node1: 438 ############################### |
| f117_search_engine_inverted_tfidf_bm25.php | FAIL_RUNTIME | exit=142| --- BM25 Search --- Query: 'quick fox'  --- Compare TF-IDF vs BM25 ---  |
| f124_container_orchestrator_pod_service_autoscale.php | FAIL_RUNTIME | exit=139|  node-1 (10.0.0.1): CPU=22.5% Mem=9.4% Pods=3   node-2 (10.0.0.2): CPU=0.0% Mem=0.0% Pods=0   node-3 (10.0.0.3): CPU=0.0% Mem=0.0% Pods=0  - |
| f135_math_number_theory_crt_miller_rabin.php | FAIL_COMPILE | Error: Compilation failed with 1 errors, 0 warnings [1mf135_math_number_theory_crt_miller_rabin.php[0m: [31merror[0m: Zig code generation failed:  |
| f151_type_system_generics_variance.php | FAIL_DIFF | PHP:=== f151: Type System + Generics + Variance + Inference ===|--- Covariant Return ---|Dog shelter: Woof||AOT:=== f151: Type System + Generics + Var |
| f160_virtual_fs_path_traversal.php | FAIL_DIFF | PHP:=== f160: Virtual FS + Path Ops + Directory Traversal ===|--- Virtual File System ---|Directory structure:||AOT:=== f160: Virtual FS + Path Ops +  |
| f161_json_xml_csv_parsing.php | FAIL_RUNTIME | exit=139|   --- XML Parsing --- PHP Warning:  Undefined variable $children in /Users/wangjianjun/products/parser/fuzzy_scripts_720/pass/f161_json_xml_ |
| f163_event_driven_dispatch_bus.php | FAIL_DIFF | PHP:=== f163: Event-Driven + PubSub + EventSourcing ===|--- Event Bus Pub/Sub ---|[Email Service] Welcome email sent to Alice||AOT:=== f163: Event-Dri |
| f171_state_machine_dfa.php | FAIL_DIFF | PHP:=== f171: State Machine + DFA + NFA ===|--- Order State Machine ---|Initial: pending||AOT:=== f171: State Machine + DFA + NFA ===|--- Order State  |
| f173_concurrency_primitives_sim.php | FAIL_DIFF | PHP:=== f173: Concurrency Primitives Simulation ===|--- Mutex ---|Lock by thread 1: OK||AOT:=== f173: Concurrency Primitives Simulation ===|--- Mutex  |
| f175_decorator_strategy_template.php | FAIL_DIFF | PHP:=== f175: Decorator + Strategy + Template Method ===|--- Decorator: Logger Formatting ---|Base: [INFO] Hello||AOT:=== f175: Decorator + Strategy + |
| f176_specification_chain_rules.php | FAIL_DIFF | PHP:=== f176: Specification Pattern + Rule Chain ===|--- Specification: User Validation ---|User evaluation:||AOT:=== f176: Specification Pattern + Ru |
| f177_graph_traversal_dfs_bfs.php | FAIL_RUNTIME | exit=139|  Vertices: A, B, C, D, E, F, G   DFS from A: A → B → D → G → E → F → C   BFS from A: A  --- Shortest Path (Dijkstra) ---  |
| f178_numeric_precision_matrix.php | FAIL_DIFF | PHP:=== f178: Numeric + Matrix + Linear Algebra ===|--- Matrix Operations ---|Matrix A:||AOT:=== f178: Numeric + Matrix + Linear Algebra ===|--- Matri |
