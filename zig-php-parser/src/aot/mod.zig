// AOT 模块导出
pub const call_graph = @import("call_graph.zig");
pub const CallGraph = call_graph.CallGraph;
pub const FunctionNode = call_graph.FunctionNode;
pub const FunctionSignature = call_graph.FunctionSignature;
pub const TypeInfo = call_graph.TypeInfo;
pub const CallEdge = call_graph.CallEdge;
pub const CallSite = call_graph.CallSite;
pub const CallType = call_graph.CallType;
pub const SourceLocation = call_graph.SourceLocation;
pub const CallPath = call_graph.CallPath;
pub const ProfileData = call_graph.ProfileData;

pub const data_flow = @import("data_flow.zig");
pub const ControlFlowGraph = data_flow.ControlFlowGraph;
pub const BasicBlock = data_flow.BasicBlock;
pub const Instruction = data_flow.Instruction;
pub const Opcode = data_flow.Opcode;
pub const Definition = data_flow.Definition;
pub const Variable = data_flow.Variable;
pub const Expression = data_flow.Expression;
pub const ExprOp = data_flow.ExprOp;
pub const DominatorTree = data_flow.DominatorTree;
pub const DataFlowAnalysis = data_flow.DataFlowAnalysis;

pub const interprocedural = @import("interprocedural.zig");
pub const InterproceduralOptimizer = interprocedural.InterproceduralOptimizer;
pub const ConstantValue = interprocedural.ConstantValue;
pub const CallSiteInfo = interprocedural.CallSiteInfo;
pub const ArgumentPattern = interprocedural.ArgumentPattern;
pub const TypePattern = interprocedural.TypePattern;
pub const SpecializedFunction = interprocedural.SpecializedFunction;
pub const ParameterInfo = interprocedural.ParameterInfo;

pub const devirtualization = @import("devirtualization.zig");
pub const DevirtualizationOptimizer = devirtualization.DevirtualizationOptimizer;
pub const ClassHierarchy = devirtualization.ClassHierarchy;
pub const ClassInfo = devirtualization.ClassInfo;
pub const VTable = devirtualization.VTable;
pub const MethodInfo = devirtualization.MethodInfo;
pub const DevirtualizationStats = devirtualization.DevirtualizationStats;

pub const bounds_check = @import("bounds_check.zig");
pub const BoundsCheckEliminator = bounds_check.BoundsCheckEliminator;
pub const InductionVarInfo = bounds_check.InductionVarInfo;
pub const ArrayLengthInfo = bounds_check.ArrayLengthInfo;

pub const reflection = @import("reflection.zig");
pub const CompileTimeReflection = reflection.CompileTimeReflection;
pub const ReflectionClassMetadata = reflection.ClassMetadata;
pub const ReflectionMethodMetadata = reflection.MethodMetadata;
pub const ReflectionPropertyMetadata = reflection.PropertyMetadata;
pub const ReflectionMethodInfo = reflection.MethodInfo;
pub const ReflectionPropertyInfo = reflection.PropertyInfo;
pub const ReflectionParameterInfo = reflection.ParameterInfo;
pub const ReflectionClassHierarchy = reflection.ClassHierarchy;
pub const ReflectionCache = reflection.ReflectionCache;
pub const ReflectionClass = reflection.ReflectionClass;

pub const dynamic_code = @import("dynamic_code.zig");
pub const DynamicCodeAnalyzer = dynamic_code.DynamicCodeAnalyzer;
pub const DynamicCodeStaticizer = dynamic_code.DynamicCodeStaticizer;
pub const DynamicFeature = dynamic_code.DynamicFeature;
pub const EvalInfo = dynamic_code.EvalInfo;
pub const VariableVariableInfo = dynamic_code.VariableVariableInfo;
pub const DynamicCallInfo = dynamic_code.DynamicCallInfo;
pub const DynamicPropertyInfo = dynamic_code.DynamicPropertyInfo;
pub const StaticizationStats = dynamic_code.StaticizationStats;

pub const lto = @import("lto.zig");
pub const LinkTimeOptimizer = lto.LinkTimeOptimizer;
pub const Module = lto.Module;
pub const Function = lto.Function;
pub const Global = lto.Global;
pub const SymbolTable = lto.SymbolTable;
pub const MergedModule = lto.MergedModule;

pub const pgo = @import("pgo.zig");
pub const Profile = pgo.Profile;
pub const ProfileGuidedOptimizer = pgo.ProfileGuidedOptimizer;
pub const Branch = pgo.Branch;
pub const BranchProfile = pgo.BranchProfile;
pub const PGOCallEdge = pgo.PGOCallEdge;
pub const FunctionInfo = pgo.FunctionInfo;
pub const BranchOptimization = pgo.BranchOptimization;
pub const BranchLayout = pgo.BranchLayout;
pub const InlineDecision = pgo.InlineDecision;
