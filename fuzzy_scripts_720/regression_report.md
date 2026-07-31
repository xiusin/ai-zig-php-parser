# fuzzy_scripts_720/pass/ 回归测试报告

测试时间: 2026-07-30 19:33:59
AOT 编译器: /Users/wangjianjun/products/parser/zig-out/bin/php-interpreter

## 统计

| 类别 | 数量 |
|------|------|
| Total | 67 |
| Pass | 16 |
| Fail (Compile) | 1 |
| Fail (Runtime) | 23 |
| Fail (Diff) | 26 |
| Skip | 1 |

## 失败明细

| 脚本 | 类型 | 详情 |
|------|------|------|
| f004_oop_deep_inheritance_magic.php | SKIP | PHP_error_exit=255 |
| f006_oop_observer_event_dispatcher.php | FAIL_DIFF | PHP:=== f006: Observer + Event Dispatcher + Priority + Exception Isolation ===|--- Event: user.login (normal) ---|[SECURITY] Checking IP: 192.168.1.1| |
| f007_string_encoding_crypto_hash.php | FAIL_RUNTIME | exit=142|djb2('Hello, World!'): 2531426958 fnv1a('Hello, World!'): 1525479220 xorHash('Hello, World!'): 8873  --- Cipher ---  |
| f009_oop_decorator_chain_command.php | FAIL_DIFF | PHP:=== f009: Decorator Chain + Command Pattern + Middleware ===|After create: created=true|After update: value=new_value||AOT:=== f009: Decorator Cha |
| f010_oop_singleton_registry_di.php | FAIL_RUNTIME | exit=139|=== f010: Singleton + Registry + DI Container ===  |
| f012_json_tree_recursive_traverse.php | FAIL_DIFF | PHP:=== f012: JSON Tree + Recursive Traverse + Path Find ===|Tree structure:|root ({"type":"dir"})||AOT:=== f012: JSON Tree + Recursive Traverse + Pat |
| f016_hash_bloom_consistent.php | FAIL_DIFF | PHP:=== f016: Hash Table + Bloom Filter + Consistent Hash ===|--- Hash Table ---|name: Alice||AOT:=== f016: Hash Table + Bloom Filter + Consistent Has |
| f024_rbac_role_inheritance_policy.php | FAIL_RUNTIME | exit=142|=== f024: RBAC + Role Inheritance + Policy === --- Permission Matrix ---                     read    write   edit    delete   Alice (admin)/a |
| f025_coding_hamming_rle_lzw_crc.php | FAIL_RUNTIME | exit=142|Round-trip OK: false After error at pos 5, decoded: '' Error corrected: false  --- RLE ---  |
| f027_number_theory_primes_modular.php | FAIL_RUNTIME | exit=139| --- Primes --- PHP Warning:  Undefined variable $primes in /Users/wangjianjun/products/parser/fuzzy_scripts_720/pass/f027_number_theory_prim |
| f028_dp_knapsack_lcs_lis.php | FAIL_RUNTIME | exit=142| Warning: Trying to access array offset on null in /Users/wangjianjun/products/parser/fuzzy_scripts_720/pass/f028_dp_knapsack_lcs_lis.php on  |
| f031_builder_fluent_immutable.php | FAIL_DIFF | PHP:=== f031: Builder + Fluent + Immutable + Freeze ===|POST https://api.example.com/v1/users?page=1&limit=20 [timeout=15s ssl=false]|Headers: {"Conte |
| f033_state_pattern_order_machine.php | FAIL_DIFF | PHP:=== f033: State Pattern + Order State Machine ===|Initial: pending|--- Paid (amount=100) ---||AOT:=== f033: State Pattern + Order State Machine == |
| f034_template_method_pipeline.php | FAIL_DIFF | PHP:=== f034: Template Method + Algorithm Skeleton + Hooks ===|--- JSON Processor ---|{"result":{"id":"123","name":"ALICE","extra":"data","processed_a |
| f037_adapter_unified_cache.php | FAIL_RUNTIME | exit=255| Fatal error: Uncaught RuntimeException: Unknown cache:  in /Users/wangjianjun/products/parser/fuzzy_scripts_720/pass/f037_adapter_unified_ca |
| f038_composite_filesystem_tree.php | FAIL_RUNTIME | exit=142|      📄 autoload.php (256B)       📄 composer.php (384B)   📄 README.md (128B)  Total size: 5120B  |
| f044_json_deepops_merge_diff.php | FAIL_DIFF | PHP:=== f044: JSON Deep Ops + Merge + Diff + Schema ===|deepGet(user.name): Alice|deepGet(user.roles.0): admin||AOT:=== f044: JSON Deep Ops + Merge +  |
| f051_validator_rule_chain_batch.php | FAIL_RUNTIME | exit=139|=== f051: Validator + Rule Chain + Batch === --- Form Validation ---  |
| f056_crdt_gcounter_lww_orset.php | FAIL_DIFF | PHP:=== f056: CRDT + GCounter + LWW + ORSet ===|--- G-Counter ---|nodeA: 5 counts={"nodeA":5}||AOT:=== f056: CRDT + GCounter + LWW + ORSet ===|--- G-C |
| f061_graph_dijkstra_bellmanford_floyd.php | FAIL_RUNTIME | exit=142|  A→E =   --- Bellman-Ford from A ---  --- Floyd-Warshall ---  |
| f065_crypto_rc4_sha1_base64_crc.php | FAIL_RUNTIME | exit=142|  CRC32('PHP') = ffffff00 (PHP: c036635b) match=false   CRC32('AOT Compiler') = ffffffff (PHP: 919b743e) match=false   CRC32('') = 00000000 ( |
| f066_hamming_code_parity_checksum.php | FAIL_DIFF | PHP:=== f066: Hamming Code + Parity + Error Correction ===|--- Hamming (7,4) ---|Data [0000] → Encoded [0000000]||AOT:=== f066: Hamming Code + Parit |
| f067_json_parser_schema_path_diff.php | FAIL_RUNTIME | exit=142| --- JSON Diff ---  --- Parse Numbers ---   '42' → NULL (type: NULL)  |
| f070_event_sourcing_cqrs_snapshot.php | FAIL_DIFF | PHP:=== f070: Event Sourcing + Snapshot + CQRS ===|--- Event Sourcing: Bank Account ---|Initial balances: acc1=0 acc2=0||AOT:=== f070: Event Sourcing  |
| f072_type_inference_hindley_milner.php | FAIL_DIFF | PHP:=== f072: Type Inference + Hindley-Milner ===|--- Literal Inference ---|42 → int||AOT:=== f072: Type Inference + Hindley-Milner ===|--- Literal  |
| f080_db_transaction_mvcc_deadlock.php | FAIL_DIFF | PHP:=== f080: DB Transaction + Isolation + MVCC + Deadlock ===|--- Basic Transaction ---|Read user:1: {"name":"Alice","balance":100}||AOT:=== f080: DB |
| f081_bplustree_index_range_query.php | FAIL_RUNTIME | exit=142|=== f081: B+Tree Index + Range Query + Pages === --- B+Tree Insert & Search ---  |
| f085_geo_rtree_knn_geocoder.php | FAIL_RUNTIME | exit=255| Fatal error: Uncaught TypeError: BoundingBox::contains(): Argument #1 ($p) must be of type Point, null given in /Users/wangjianjun/products/ |
| f087_rbac_abac_policy_inheritance.php | FAIL_COMPILE | [1m<unknown>[0m: [31merror[0m: Zig compiler failed with exit code 1 [1mf087_rbac_abac_policy_inheritance.php[0m: [31merror[0m: executable gene |
| f095_compiler_opt_constfold_dce_cse.php | FAIL_RUNTIME | exit=142|  c3 = const(10)   t4 = const(7)   ret t2  --- Dead Code Elimination ---  |
| f097_search_engine_inverted_index_tfidf.php | FAIL_DIFF | PHP:=== f097: Search Engine + InvertedIndex + TF-IDF ===|--- Build Index ---|Documents: 6||AOT:=== f097: Search Engine + InvertedIndex + TF-IDF ===|-- |
| f102_memory_gc_marksweep_refcount_gen.php | FAIL_RUNTIME | exit=142|--- Cycle Detection --- Cycle detection: 0 cycles found  --- Generational GC --- Total objects: 15  |
| f104_game_engine_ecs_collision_render.php | FAIL_RUNTIME | exit=142| --- Entity States ---    Entity 1: pos=(150,300) hp=100/100 sprite=   Entity 2: pos=(370,310) hp=50/50 sprite=  |
| f105_db_index_btree_hash_queryplan.php | FAIL_DIFF | PHP:=== f105: DB Index + BTree + HashIndex + QueryPlan ===|--- B-Tree Index ---|Inserted: 10, 20, 5, 6, 12, 30, 7, 17, 25, 31, 3, 1, 40, 50, 15, 8, 45 |
| f110_os_sim_process_memory_filesystem.php | FAIL_RUNTIME | exit=139|home/user:  Readme:  Config: key=value After delete readme, home/user:  === f110 Done ===  |
| f113_distributed_consistenthash_vectorclock_quorum.php | FAIL_DIFF | PHP:=== f113: Distributed + ConsistentHash + VectorClock + Quorum ===|--- Consistent Hashing ---|Distribution (1000 keys):||AOT:=== f113: Distributed  |
| f117_search_engine_inverted_tfidf_bm25.php | FAIL_DIFF | PHP:=== f117: Search Engine + InvertedIndex + TF-IDF + BM25 ===|--- Build Index ---|Index stats: {"documents":7,"terms":20,"avg_doc_length":5.7}||AOT: |
| f119_logging_structured_levels_rotation.php | FAIL_DIFF | PHP:=== f119: Logging + Structured + Levels + Rotation ===|--- Basic Logging ---|[info] app: User logged in {"user":"alice","ip":"192.168.1.1"}||AOT:= |
| f124_container_orchestrator_pod_service_autoscale.php | FAIL_RUNTIME | exit=139|  node-1 (10.0.0.1): CPU=22.5% Mem=9.4% Pods=3   node-2 (10.0.0.2): CPU=0.0% Mem=0.0% Pods=0   node-3 (10.0.0.3): CPU=0.0% Mem=0.0% Pods=0  - |
| f135_math_number_theory_crt_miller_rabin.php | FAIL_RUNTIME | exit=142|modInverse(3, 11) = 4 (expected 4) modInverse(7, 26) = 15 (expected 15) Verify: 3*4 mod 11 = 1  --- Modular Exponentiation ---  |
| f151_type_system_generics_variance.php | FAIL_DIFF | PHP:=== f151: Type System + Generics + Variance + Inference ===|--- Covariant Return ---|Dog shelter: Woof||AOT:=== f151: Type System + Generics + Var |
| f160_virtual_fs_path_traversal.php | FAIL_DIFF | PHP:=== f160: Virtual FS + Path Ops + Directory Traversal ===|--- Virtual File System ---|Directory structure:||AOT:=== f160: Virtual FS + Path Ops +  |
| f161_json_xml_csv_parsing.php | FAIL_RUNTIME | exit=142|    Bob: 25   By city:     0: Alice, Bob, Charlie, Diana    Generated CSV:  |
| f163_event_driven_dispatch_bus.php | FAIL_DIFF | PHP:=== f163: Event-Driven + PubSub + EventSourcing ===|--- Event Bus Pub/Sub ---|[Email Service] Welcome email sent to Alice||AOT:=== f163: Event-Dri |
| f164_plugin_hook_system.php | FAIL_DIFF | PHP:=== f164: Plugin System + Hooks + Lifecycle ===|--- Register Plugins ---|Registered: seo, cache, analytics||AOT:=== f164: Plugin System + Hooks +  |
| f171_state_machine_dfa.php | FAIL_DIFF | PHP:=== f171: State Machine + DFA + NFA ===|--- Order State Machine ---|Initial: pending||AOT:=== f171: State Machine + DFA + NFA ===|--- Order State  |
| f173_concurrency_primitives_sim.php | FAIL_DIFF | PHP:=== f173: Concurrency Primitives Simulation ===|--- Mutex ---|Lock by thread 1: OK||AOT:=== f173: Concurrency Primitives Simulation ===|--- Mutex  |
| f175_decorator_strategy_template.php | FAIL_RUNTIME | exit=142| --- Strategy: Sorting ---   Original: 64, 34, 25, 12, 22, 11, 90, 1, 45, 33   BubbleSort: 1, 11, 12, 22, 25, 33, 34, 45, 64, 90   QuickSort: |
| f176_specification_chain_rules.php | FAIL_DIFF | PHP:=== f176: Specification Pattern + Rule Chain ===|--- Specification: User Validation ---|User evaluation:||AOT:=== f176: Specification Pattern + Ru |
| f177_graph_traversal_dfs_bfs.php | FAIL_RUNTIME | exit=139|=== f177: Graph Algorithms + DFS/BFS/ShortestPath === --- Undirected Graph: DFS/BFS ---   Vertices: A, B, C, D, E, F, G  |
| f178_numeric_precision_matrix.php | FAIL_DIFF | PHP:=== f178: Numeric + Matrix + Linear Algebra ===|--- Matrix Operations ---|Matrix A:||AOT:=== f178: Numeric + Matrix + Linear Algebra ===|--- Matri |
