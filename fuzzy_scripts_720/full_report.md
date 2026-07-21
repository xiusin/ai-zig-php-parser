# fuzzy_scripts_720 全量测试报告 v2

测试时间: 2026-07-21 08:53:24

## 统计

| 类别 | 数量 |
|------|------|
| Pass | 61 |
| Fail (Compile) | 18 |
| Fail (Runtime/Diff) | 77 |
| 根目录待测 | 24 |
| 累计已测 | 24 |

## 失败明细

| 脚本 | 类型 | 详情 |
|------|------|------|
| f026_linkedlist_stack_queue_deque.php | PASS |  |
| f027_number_theory_primes_modular.php | PASS |  |
| f028_dp_knapsack_lcs_lis.php | PASS |  |
| f029_backtracking_nqueens_perm_maze.php | FAIL_COMPILE | [1m<unknown>[0m: [31merror[0m: Zig compiler failed with exit code 1 [1mf029_backtracking_nqueens_perm_maze.php[0m: [31merror[0m: executable ge |
| f030_greedy_huffman_scheduling.php | FAIL_COMPILE | [1m<unknown>[0m: [31merror[0m: Zig compiler failed with exit code 1 [1mf030_greedy_huffman_scheduling.php[0m: [31merror[0m: executable generat |
| f031_builder_fluent_immutable.php | PASS |  |
| f032_chain_responsibility_middleware.php | PASS |  |
| f033_state_pattern_order_machine.php | PASS |  |
| f034_template_method_pipeline.php | PASS |  |
| f035_prototype_deep_clone.php | SKIP | PHP_error_exit=255 |
| f036_strategy_dynamic_pricing.php | PASS |  |
| f037_adapter_unified_cache.php | PASS |  |
| f038_composite_filesystem_tree.php | PASS |  |
| f039_bridge_shape_renderer.php | PASS |  |
| f040_flyweight_forest_pool.php | PASS |  |
| f041_string_functions_full.php | FAIL_DIFF | PHP:=== f041: String Functions Full Suite ===|contains('Hello'): true|startsWith('Hello'): true||AOT:=== f041: String Functions Full Suite ===|contain |
| f042_array_functions_full.php | FAIL_COMPILE | [1m<unknown>[0m: [31merror[0m: Zig compiler failed with exit code 1 [1mf042_array_functions_full.php[0m: [31merror[0m: executable generation f |
| f043_math_functions_full.php | FAIL_COMPILE | [1m<unknown>[0m: [31merror[0m: Zig compiler failed with exit code 1 [1mf043_math_functions_full.php[0m: [31merror[0m: executable generation fa |
| f044_json_deepops_merge_diff.php | PASS |  |
| f045_datetime_calendar_format.php | PASS |  |
| f046_exception_handling_chain.php | FAIL_RUNTIME | exit=255| Fatal error: Uncaught TypeError: ExceptionHandler::handle(): Argument #1 ($e) must be of type Throwable, NotFoundException given in /Users/t |
| f047_closures_curry_compose.php | FAIL_COMPILE | [1m<unknown>[0m: [31merror[0m: Zig compiler failed with exit code 1 [1mf047_closures_curry_compose.php[0m: [31merror[0m: executable generation |
| f048_match_pattern_dispatch.php | PASS |  |
| f049_type_system_union_guards.php | FAIL_DIFF | PHP:=== f049: Type System + Union + Guards + instanceof ===|--- Animal Type Guards ---|Duck says Quack! | Duck swimming | Duck flying||AOT:=== f049: T |
| f050_iterator_generator_filter_map.php | SKIP | PHP_error_exit=255 |
| f051_validator_rule_chain_batch.php | PASS |  |
| f052_template_engine_render.php | SKIP | PHP_error_exit=255 |
| f053_query_builder_sql.php | SKIP | PHP_error_exit=255 |
| f054_signal_waveform_filter.php | FAIL_DIFF | PHP:=== f054: Signal Processing + Waveform + FFT ===|--- Waveform Generation ---|Sine (5Hz, 0.2s, 10 samples): [0.000, 0.588, 0.951, 0.951, 0.588, 0.0 |
| f055_ml_perceptron_kmeans_regression.php | FAIL_RUNTIME | exit=139|  predict([0,1]) = 1 (expected 1)   predict([1,0]) = 1 (expected 1)   predict([1,1]) = 1 (expected 1)  --- KMeans Clustering ---  |
| f056_crdt_gcounter_lww_orset.php | PASS |  |
| f057_workflow_engine_rollback.php | PASS |  |
| f058_nfa_string_search_kmp.php | FAIL_RUNTIME | exit=139|=== f058: NFA + String Search + Pattern Match === --- NFA Matching --- match 'ab' on 'ab': false match 'ab' on 'abc': false match 'ab' on 'ac |
| f059_consensus_raft_election.php | FAIL_DIFF | PHP:=== f059: Consensus + Raft Sim + Leader Election ===|--- 5-Node Cluster ---|Starting election (node 2):||AOT:=== f059: Consensus + Raft Sim + Lead |
| f060_connection_pool_heartbeat.php | FAIL_DIFF | PHP:=== f060: Connection Pool + Heartbeat + Health + LoadBalance ===|--- Initial State ---|{"pool_size":2,"in_use":0,"total":2,"alive":2}||AOT:=== f06 |
| f061_graph_dijkstra_bellmanford_floyd.php | PASS |  |
| f062_network_flow_maxflow_mincut.php | FAIL_RUNTIME | exit=124|=== f062: Network Flow + MaxFlow + MinCut + Bipartite === --- Max Flow ---  |
| f063_lexer_parser_ast_eval.php | SKIP | excluded |
| f064_matrix_det_inverse_eigenvalue.php | FAIL_COMPILE | [1m<unknown>[0m: [31merror[0m: Zig compiler failed with exit code 1 [1mf064_matrix_det_inverse_eigenvalue.php[0m: [31merror[0m: executable gen |
| f065_crypto_rc4_sha1_base64_crc.php | PASS |  |
| f066_hamming_code_parity_checksum.php | PASS |  |
| f067_json_parser_schema_path_diff.php | PASS |  |
| f068_cache_lru_lfu_ttl_multilevel.php | FAIL_DIFF | PHP:=== f068: Cache System + LRU + LFU + TTL + MultiLevel ===|--- LRU Cache ---|PHP Deprecated:  Implicit conversion from float 1784546342.260074 to i |
| f069_message_queue_pubsub_deadletter.php | FAIL_DIFF | PHP:=== f069: Message Queue + PubSub + DeadLetter + Delay ===|--- Message Queue ---|Queue sizes: orders=3 notifications=1||AOT:=== f069: Message Queue |
| f070_event_sourcing_cqrs_snapshot.php | PASS |  |
| f071_compression_huffman_rle_lz77.php | FAIL_COMPILE | [1m<unknown>[0m: [31merror[0m: Zig compiler failed with exit code 1 [1mf071_compression_huffman_rle_lz77.php[0m: [31merror[0m: executable gene |
| f072_type_inference_hindley_milner.php | PASS |  |
| f073_di_container_autowire_lifecycle.php | FAIL_DIFF | PHP:=== f073: DI Container + Autowire + Lifecycle ===|--- Resolve UserService ---|[LOG] Cache miss, fetching user 1||AOT:=== f073: DI Container + Auto |
| f074_rule_engine_conditions_actions.php | FAIL_DIFF | PHP:=== f074: Rule Engine + Conditions + Actions ===|--- E-commerce Discount Rules ---|VIP buying $200 phone:||AOT:=== f074: Rule Engine + Conditions  |
| f075_orm_querybuilder_relations.php | SKIP | PHP_error_exit=255 |
| f076_state_machine_guards_nested.php | FAIL_RUNTIME | exit=255| Fatal error: Uncaught TypeError: State::__construct(): Argument #2 ($substates) must be of type array, unknown given in /Users/tuoke/Desktop |
| f077_websocket_frame_protocol_rooms.php | FAIL_DIFF | PHP:=== f077: WebSocket Frame + Protocol + Broadcast + Rooms ===|--- WebSocket Frame Encode/Decode ---|text (len=5) → encoded 11 bytes, match=true|| |
| f078_rate_limiter_token_sliding_leaky.php | FAIL_DIFF | PHP:=== f078: Rate Limiter + TokenBucket + SlidingWindow ===|--- Token Bucket ---|First burst: allowed=5 denied=5 (capacity=5)||AOT:=== f078: Rate Lim |
| f079_scheduler_priority_dependencies_toposort.php | FAIL_DIFF | PHP:=== f079: Scheduler + Priority + Dependencies + TopoSort ===|--- Build Pipeline ---|Topological order: fetch → compile → test → lint → pac |
| f080_db_transaction_mvcc_deadlock.php | PASS |  |
| f081_bplustree_index_range_query.php | PASS |  |
| f082_template_engine_compile_filter.php | FAIL_RUNTIME | exit=139|--- Conditionals --- Adult  (age=25)  Minor (age=15)  --- Loops ---  |
| f083_interpreter_visitor_scope.php | SKIP | excluded |
| f084_test_framework_assert_mock.php | FAIL_RUNTIME | exit=255| Fatal error: Uncaught Error: Class "AssertionError" not found in /Users/tuoke/Desktop/ai-zig-php-parser/fuzzy_scripts_720/f084_test_framewor |
| f085_geo_rtree_knn_geocoder.php | PASS |  |
| f086_config_center_hotreload_version.php | FAIL_DIFF | PHP:=== f086: Config Center + Hot Reload + Version ===|--- Config Center (Development) ---|Env: development||AOT:=== f086: Config Center + Hot Reload  |
| f087_rbac_abac_policy_inheritance.php | PASS |  |
| f088_distributed_lock_redlock_lease.php | FAIL_DIFF | PHP:=== f088: Distributed Lock + RedLock + Lease ===|--- Single Node Lock ---|Acquire 'task1' by Alice: true||AOT:=== f088: Distributed Lock + RedLock |
| f089_blockchain_pow_merkle_tx.php | FAIL_COMPILE | [1m<unknown>[0m: [31merror[0m: Zig compiler failed with exit code 1 [1mf089_blockchain_pow_merkle_tx.php[0m: [31merror[0m: executable generati |
| f090_promise_future_async_concurrent.php | PASS |  |
| f091_os_scheduler_banker_algorithm.php | FAIL_COMPILE | [1m<unknown>[0m: [31merror[0m: Zig compiler failed with exit code 1 [1mf091_os_scheduler_banker_algorithm.php[0m: [31merror[0m: executable gen |
| f092_physics_collision_rigidbody.php | SKIP | PHP_error_exit=255 |
| f093_neural_network_backprop.php | SKIP | PHP_error_exit=255 |
| f094_regex_engine_nfa_capture.php | FAIL_DIFF | PHP:=== f094: Regex Engine + NFA + Capture Groups ===|--- Simple Pattern Matching ---|Pattern: abc||AOT:=== f094: Regex Engine + NFA + Capture Groups  |
| f095_compiler_opt_constfold_dce_cse.php | PASS |  |
| f096_timezone_calendar_timeseries.php | FAIL_RUNTIME | exit=124|Feb 2023 days: 28 Q1 of March: 1 Q3 of August: 3  --- Date Range ---  |
| f097_search_engine_inverted_index_tfidf.php | PASS |  |
| f098_loadbalancer_strategy_health_circuit.php | FAIL_DIFF | PHP:=== f098: LoadBalancer + Strategies + Health + Circuit ===|--- Round Robin ---|Stats: {"total":20,"success":18,"error":2,"rejected":0}||AOT:=== f0 |
| f099_image_processing_convolution_filter.php | FAIL_DIFF | PHP:=== f099: Image Processing + Convolution + Filter ===|--- Generate Image ---|Gradient 8x8:||AOT:=== f099: Image Processing + Convolution + Filter  |
| f100_automata_dfa_minimize_regex.php | FAIL_DIFF | PHP:=== f100: Automata + DFA Minimization + Regex Equiv ===|--- DFA: Accepts strings ending in 'ab' ---|PHP Deprecated:  Creation of dynamic property  |
| f101_dataflow_liveness_reachingdef.php | FAIL_DIFF | PHP:=== f101: Data Flow Analysis + Liveness + ReachingDef ===|--- Build CFG ---|CFG:||AOT:=== f101: Data Flow Analysis + Liveness + ReachingDef ===|-- |
| f102_memory_gc_marksweep_refcount_gen.php | PASS |  |
| f103_crypto_rsa_dh_signature.php | FAIL_RUNTIME | exit=255| Fatal error: Uncaught TypeError: MathUtils::gcd(): Argument #1 ($a) must be of type int, null given in /Users/tuoke/Desktop/ai-zig-php-parse |
| f104_game_engine_ecs_collision_render.php | PASS |  |
| f105_db_index_btree_hash_queryplan.php | PASS |  |
| f106_network_tcp_sliding_window_congestion.php | FAIL_DIFF | PHP:=== f106: Network Stack + TCP + SlidingWindow + Congestion ===|--- TCP 3-Way Handshake ---|Client sends SYN||AOT:=== f106: Network Stack + TCP + S |
| f107_functional_curry_compose_lazy_monad.php | SKIP | excluded |
| f108_code_generator_ast_template_serialize.php | FAIL_RUNTIME | exit=139|        }     ] }  --- Deserialize from JSON ---  |
| f109_compiler_backend_regalloc_peephole.php | SKIP | PHP_error_exit=255 |
| f110_os_sim_process_memory_filesystem.php | PASS |  |
| f111_type_system_hm_inference_unification.php | FAIL_RUNTIME | exit=255| Fatal error: Uncaught Exception: If condition must be Bool in /Users/tuoke/Desktop/ai-zig-php-parser/fuzzy_scripts_720/f111_type_system_hm_i |
| f112_timeseries_db_downsample_aggregate.php | FAIL_RUNTIME | exit=139|  t=999600 median=52.485 count=4   t=1000200 median=66.3543 count=10   t=1000800 median=68.477 count=7  --- Aggregation (stddev per 10 min) - |
| f113_distributed_consistenthash_vectorclock_quorum.php | PASS |  |
| f114_geometry_convexhull_closestpair_intersect.php | FAIL_DIFF | PHP:=== f114: Computational Geometry + ConvexHull + ClosestPair ===|--- Convex Hull (Graham Scan) ---|Points: (0,0), (2,0), (1,1), (2,2), (0,2), (0.5, |
| f115_ml_decisiontree_naivebayes_knn.php | FAIL_RUNTIME | exit=255| Fatal error: Uncaught TypeError: Unsupported operand types: float + string in /Users/tuoke/Desktop/ai-zig-php-parser/fuzzy_scripts_720/f115_ |
| f116_state_machine_hierarchical_history_parallel.php | FAIL_DIFF | PHP:=== f116: StateMachine + Hierarchical + History + Parallel ===|--- Basic State Machine ---|After 'start': state=running||AOT:=== f116: StateMachin |
| f117_search_engine_inverted_tfidf_bm25.php | FAIL_COMPILE | [1m<unknown>[0m: [31merror[0m: Zig compiler failed with exit code 1 [1mf117_search_engine_inverted_tfidf_bm25.php[0m: [31merror[0m: executable |
| f118_orm_active_record_querybuilder_migration.php | SKIP | PHP_error_exit=255 |
| f119_logging_structured_levels_rotation.php | PASS |  |
| f120_message_queue_kafka_partition_consumer.php | FAIL_RUNTIME | exit=139|  consumer-3: [2]  After consumer-2 leaves:   consumer-1: [0, 2]   consumer-3: [1]  |
| f121_compiler_opt_constprop_dce_cse.php | SKIP | PHP_error_exit=255 |
| f122_scheduler_priority_dependency_criticalpath.php | SKIP | PHP_error_exit=255 |
| f123_network_traffic_packet_protocol_flow.php | SKIP | PHP_error_exit=255 |
| f124_container_orchestrator_pod_service_autoscale.php | PASS |  |
| f125_compression_huffman_lz77_rle_arithmetic.php | FAIL_RUNTIME | exit=139|Compressed: 0361036203630564046505660267 (14 bytes) Decompressed: aaabbbcccdddddeeeefffffgg Match: true  --- Huffman Coding ---  |
| f126_security_auth_rbac_abac_audit.php | FAIL_DIFF | PHP:=== f126: Security + Auth + RBAC + Audit ===|--- Setup Auth ---|Users: 3||AOT:=== f126: Security + Auth + RBAC + Audit ===|--- Setup Auth ---|User |
| f127_graph_mst_bridge_articulation_scc.php | FAIL_DIFF | PHP:=== f127: Graph + MST + Bridge + Articulation + SCC ===|--- Minimum Spanning Tree ---|Kruskal MST: total=37||AOT:=== f127: Graph + MST + Bridge +  |
| f128_linear_algebra_matrix_lu_qr_eigenvalue.php | FAIL_COMPILE | [1m<unknown>[0m: [31merror[0m: Zig compiler failed with exit code 1 [1mf128_linear_algebra_matrix_lu_qr_eigenvalue.php[0m: [31merror[0m: execu |
| f129_regex_engine_nfa_backtrack_capture.php | FAIL_COMPILE | [1m<unknown>[0m: [31merror[0m: Zig compiler failed with exit code 1 [1mf129_regex_engine_nfa_backtrack_capture.php[0m: [31merror[0m: executabl |
| f130_test_framework_assert_mock_coverage.php | SKIP | PHP_error_exit=255 |
| f131_physics_rigidbody_collision_gravity_spring.php | SKIP | PHP_error_exit=255 |
| f132_config_center_multienv_hotreload_version.php | FAIL_DIFF | PHP:=== f132: Config Center + MultiEnv + HotReload + Version ===|--- Setup Config Sources ---|Version: 2||AOT:=== f132: Config Center + MultiEnv + Hot |
| f133_blockchain_pow_merkle_txpool_contract.php | FAIL_DIFF | PHP:=== f133: Blockchain + PoW + Merkle + TxPool + Contract ===|--- Create Blockchain ---|Genesis block hash: 00338f6c3357ee0e61e2...||AOT:=== f133: B |
| f134_event_sourcing_snapshot_cqrs_projection.php | PASS |  |
| f135_math_number_theory_crt_miller_rabin.php | PASS |  |
| f136_database_mvcc_isolation_deadlock_wal.php | SKIP | PHP_error_exit=255 |
| f137_template_engine_compile_filter_inheritance.php | FAIL_RUNTIME | exit=139|Array 19.999 {"a":1,"b":2}  --- Conditionals ---  |
| f138_neural_network_forward_backprop_activation.php | FAIL_COMPILE | [1m<unknown>[0m: [31merror[0m: Zig compiler failed with exit code 1 [1mf138_neural_network_forward_backprop_activation.php[0m: [31merror[0m: e |
| f139_string_algo_suffix_lcs_editdistance.php | FAIL_DIFF | PHP:=== f139: String Algo + SuffixArray + LCS + EditDistance ===|--- Edit Distance ---|'kitten' → 'sitting': distance=3||AOT:=== f139: String Algo + |
| f140_rule_engine_condition_action_priority.php | FAIL_DIFF | PHP:=== f140: Rule Engine + Condition + Action + Priority ===|--- Shopping Cart Discount Rules ---|Case 1: total=$600 → discount=$180 shipping=$0 su |
| f141_monitoring_metrics_alerting_aggregation.php | FAIL_DIFF | PHP:=== f141: Monitoring + Metrics + Alerting + Aggregation ===|--- Setup Monitoring ---|--- Simulate Metrics ---||AOT:=== f141: Monitoring + Metrics  |
| f142_cicd_pipeline_stage_parallel_artifact.php | FAIL_DIFF | PHP:=== f142: CICD + Pipeline + Stage + Parallel + Artifact ===|--- Build Pipeline ---|Pipeline 'build-deploy' started (trigger: push)||AOT:=== f142:  |
| f143_code_generator_ast_template_dsl.php | SKIP | PHP_error_exit=255 |
| f144_graphics_rasterize_zbuffer_lighting_shading.php | SKIP | PHP_error_exit=255 |
| f145_geospatial_rtree_nearest_routing.php | FAIL_DIFF | PHP:=== f145: GeoSpatial + RTree + NearestNeighbor + Routing ===|--- GeoPoints ---|New York(40.7128,-74.006)||AOT:=== f145: GeoSpatial + RTree + Neare |
| f146_formal_verification_modelcheck_invariant_fuzz.php | FAIL_RUNTIME | exit=139| --- Fuzz String Parser --- PHP Warning:  Undefined variable $maxLen in /Users/tuoke/Desktop/ai-zig-php-parser/fuzzy_scripts_720/f146_formal_ |
| f147_workflow_engine_bpmn_gateway_subprocess_compensation.php | SKIP | PHP_error_exit=255 |
| f148_dsp_fft_filter_convolution_spectrum.php | FAIL_COMPILE | [1m<unknown>[0m: [31merror[0m: Zig compiler failed with exit code 1 [1mf148_dsp_fft_filter_convolution_spectrum.php[0m: [31merror[0m: executab |
| f149_ml_clustering_pca_crossvalidation_feature.php | FAIL_COMPILE | [1m<unknown>[0m: [31merror[0m: Zig compiler failed with exit code 1 [1mf149_ml_clustering_pca_crossvalidation_feature.php[0m: [31merror[0m: ex |
| f150_distributed_raft_log_replication_election_statemachine.php | SKIP | PHP_error_exit=255 |
| f151_type_system_generics_variance.php | PASS |  |
| f152_closure_arrow_higher_order.php | FAIL_COMPILE | [1m<unknown>[0m: [31merror[0m: Zig compiler failed with exit code 1 [1mf152_closure_arrow_higher_order.php[0m: [31merror[0m: executable genera |
| f153_exception_hierarchy_chaining.php | FAIL_RUNTIME | exit=255| Fatal error: Uncaught TypeError: ExceptionHandler::handle(): Argument #1 ($e) must be of type Throwable, null given in /Users/tuoke/Desktop/ |
| f154_match_expression_enums.php | FAIL_RUNTIME | exit=255| Fatal error: Uncaught TypeError: createRect(): Argument #4 ($$filled) must be of type bool, unknown given in /Users/tuoke/Desktop/ai-zig-php |
| f155_trait_composition_conflict.php | FAIL_DIFF | PHP:=== f155: Trait Composition + Conflict Resolution ===|--- Trait Conflict Resolution ---|A::hello: Hello from A||AOT:=== f155: Trait Composition +  |
| f156_iterator_generator_aggregate.php | SKIP | excluded |
| f157_string_multibyte_tokenize_template.php | FAIL_RUNTIME | exit=255| Fatal error: Uncaught Error: Call to undefined function mb_split() in /Users/tuoke/Desktop/ai-zig-php-parser/fuzzy_scripts_720/f157_string_m |
| f158_array_advanced_functional.php | FAIL_RUNTIME | exit=255| Fatal error: Uncaught TypeError: ArrayUtils::zip(): Argument #1 ($arrays) must be of type array, null given in /Users/tuoke/Desktop/ai-zig-p |
| f159_date_time_timezone_duration.php | FAIL_DIFF | PHP:=== f159: DateTime + Timezone + Duration + Calendar ===|--- Days Between ---|2026-01-01 to 2026-12-31: 364 days||AOT:=== f159: DateTime + Timezone |
| f160_virtual_fs_path_traversal.php | FAIL_COMPILE | [1m<unknown>[0m: [31merror[0m: Zig compiler failed with exit code 1 [1mf160_virtual_fs_path_traversal.php[0m: [31merror[0m: executable generat |
| f161_json_xml_csv_parsing.php | PASS |  |
| f162_crypto_hash_hmac_sign.php | FAIL_COMPILE | [1m<unknown>[0m: [31merror[0m: Zig compiler failed with exit code 1 [1mf162_crypto_hash_hmac_sign.php[0m: [31merror[0m: executable generation  |
| f163_event_driven_dispatch_bus.php | PASS |  |
| f164_plugin_hook_system.php | PASS |  |
| f165_promise_async_simulation.php | FAIL_RUNTIME | exit=255| Fatal error: Uncaught TypeError: Promise::reject(): Argument #1 ($error) must be of type Throwable, Exception given in /Users/tuoke/Desktop/ |
| f166_etl_pipeline_transform.php | FAIL_DIFF | PHP:=== f166: ETL Pipeline + Transform + Validate ===|--- ETL Pipeline: User Data ---|Input: 8 records||AOT:=== f166: ETL Pipeline + Transform + Valid |
| f167_reactive_streams_observer.php | FAIL_DIFF | PHP:=== f167: Reactive Streams + Observer + Operators ===|--- Basic Observable ---|fromArray: 1, 2, 3, 4, 5||AOT:=== f167: Reactive Streams + Observer |
| f168_interpreter_pattern_eval.php | SKIP | PHP_error_exit=255 |
| f169_builder_pattern_fluent.php | FAIL_RUNTIME | exit=139|  SELECT id, name, email FROM users WHERE age > 18 AND status = 'active' ORDER BY name ASC LIMIT 10   SELECT orders.id, users.name, products. |
| f170_dependency_injection_container.php | FAIL_RUNTIME | exit=255| Fatal error: Uncaught Exception: Cannot resolve parameter $path for FileLogger in /Users/tuoke/Desktop/ai-zig-php-parser/fuzzy_scripts_720/f |
| f171_state_machine_dfa.php | PASS |  |
| f172_memory_pool_object_pool.php | FAIL_DIFF | PHP:=== f172: Memory Pool + Object Pool + Buffer ===|--- Object Pool (Buffer) ---|After acquiring 5 buffers:||AOT:=== f172: Memory Pool + Object Pool  |
| f173_concurrency_primitives_sim.php | PASS |  |
| f174_command_undo_redo_macro.php | PASS |  |
| f175_decorator_strategy_template.php | PASS |  |
| f176_specification_chain_rules.php | PASS |  |
| f177_graph_traversal_dfs_bfs.php | PASS |  |
| f178_numeric_precision_matrix.php | PASS |  |
| f179_visitor_composite_ast.php | PASS |  |
| f180_middleware_pipeline_chain.php | FAIL_DIFF | PHP:=== f180: Middleware Pipeline + Onion Model ===|--- Basic Pipeline ---|[LOG] → GET /api/hello||AOT:=== f180: Middleware Pipeline + Onion Model = |
| f035_prototype_deep_clone.php | SKIP | PHP_error_exit=255 |
| f050_iterator_generator_filter_map.php | SKIP | PHP_error_exit=255 |
| f052_template_engine_render.php | SKIP | PHP_error_exit=255 |
| f053_query_builder_sql.php | SKIP | PHP_error_exit=255 |
| f063_lexer_parser_ast_eval.php | SKIP | excluded |
| f075_orm_querybuilder_relations.php | SKIP | PHP_error_exit=255 |
| f083_interpreter_visitor_scope.php | SKIP | excluded |
| f092_physics_collision_rigidbody.php | SKIP | PHP_error_exit=255 |
| f093_neural_network_backprop.php | SKIP | PHP_error_exit=255 |
| f107_functional_curry_compose_lazy_monad.php | SKIP | excluded |
| f109_compiler_backend_regalloc_peephole.php | SKIP | PHP_error_exit=255 |
| f118_orm_active_record_querybuilder_migration.php | SKIP | PHP_error_exit=255 |
| f121_compiler_opt_constprop_dce_cse.php | SKIP | PHP_error_exit=255 |
| f122_scheduler_priority_dependency_criticalpath.php | SKIP | PHP_error_exit=255 |
| f123_network_traffic_packet_protocol_flow.php | SKIP | PHP_error_exit=255 |
| f130_test_framework_assert_mock_coverage.php | SKIP | PHP_error_exit=255 |
| f131_physics_rigidbody_collision_gravity_spring.php | SKIP | PHP_error_exit=255 |
| f136_database_mvcc_isolation_deadlock_wal.php | SKIP | PHP_error_exit=255 |
| f143_code_generator_ast_template_dsl.php | SKIP | PHP_error_exit=255 |
| f144_graphics_rasterize_zbuffer_lighting_shading.php | SKIP | PHP_error_exit=255 |
| f147_workflow_engine_bpmn_gateway_subprocess_compensation.php | SKIP | PHP_error_exit=255 |
| f150_distributed_raft_log_replication_election_statemachine.php | SKIP | PHP_error_exit=255 |
| f156_iterator_generator_aggregate.php | SKIP | excluded |
| f168_interpreter_pattern_eval.php | SKIP | PHP_error_exit=255 |
| f035_prototype_deep_clone.php | SKIP | PHP_error_exit=255 |
| f050_iterator_generator_filter_map.php | SKIP | PHP_error_exit=255 |
| f052_template_engine_render.php | SKIP | PHP_error_exit=255 |
| f053_query_builder_sql.php | SKIP | PHP_error_exit=255 |
| f063_lexer_parser_ast_eval.php | SKIP | excluded |
| f075_orm_querybuilder_relations.php | SKIP | PHP_error_exit=255 |
| f083_interpreter_visitor_scope.php | SKIP | excluded |
| f092_physics_collision_rigidbody.php | SKIP | PHP_error_exit=255 |
| f093_neural_network_backprop.php | SKIP | PHP_error_exit=255 |
| f107_functional_curry_compose_lazy_monad.php | SKIP | excluded |
| f109_compiler_backend_regalloc_peephole.php | SKIP | PHP_error_exit=255 |
| f118_orm_active_record_querybuilder_migration.php | SKIP | PHP_error_exit=255 |
| f121_compiler_opt_constprop_dce_cse.php | SKIP | PHP_error_exit=255 |
| f122_scheduler_priority_dependency_criticalpath.php | SKIP | PHP_error_exit=255 |
| f123_network_traffic_packet_protocol_flow.php | SKIP | PHP_error_exit=255 |
| f130_test_framework_assert_mock_coverage.php | SKIP | PHP_error_exit=255 |
| f131_physics_rigidbody_collision_gravity_spring.php | SKIP | PHP_error_exit=255 |
| f136_database_mvcc_isolation_deadlock_wal.php | SKIP | PHP_error_exit=255 |
| f143_code_generator_ast_template_dsl.php | SKIP | PHP_error_exit=255 |
| f144_graphics_rasterize_zbuffer_lighting_shading.php | SKIP | PHP_error_exit=255 |
| f147_workflow_engine_bpmn_gateway_subprocess_compensation.php | SKIP | PHP_error_exit=255 |
| f150_distributed_raft_log_replication_election_statemachine.php | SKIP | PHP_error_exit=255 |
| f156_iterator_generator_aggregate.php | SKIP | excluded |
| f168_interpreter_pattern_eval.php | SKIP | PHP_error_exit=255 |
