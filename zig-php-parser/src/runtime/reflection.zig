const std = @import("std");
const types = @import("types.zig");
const Value = types.Value;
const PHPClass = types.PHPClass;
const PHPObject = types.PHPObject;
const Method = types.Method;
const Property = types.Property;
const PHPString = types.PHPString;
const UserFunction = types.UserFunction;
const PHPArray = types.PHPArray;
const ArrayKey = types.ArrayKey;
const gc = @import("gc.zig");

// Forward declaration for VM
const VM = @import("vm.zig").VM;

/// ReflectionClass provides runtime introspection of PHP classes
pub const ReflectionClass = struct {
    class: *PHPClass,
    allocator: std.mem.Allocator,
    
    pub fn init(allocator: std.mem.Allocator, class: *PHPClass) ReflectionClass {
        return ReflectionClass{
            .class = class,
            .allocator = allocator,
        };
    }
    
    pub fn getName(self: *const ReflectionClass) *PHPString {
        return self.class.name;
    }
    
    pub fn getShortName(self: *ReflectionClass) !*PHPString {
        const full_name = self.class.name.data;
        
        // Find the last backslash for namespace separation
        var last_backslash: ?usize = null;
        for (full_name, 0..) |char, i| {
            if (char == '\\') {
                last_backslash = i;
            }
        }
        
        const short_name = if (last_backslash) |pos| 
            full_name[pos + 1..] 
        else 
            full_name;
            
        return PHPString.init(self.allocator, short_name);
    }
    
    pub fn getNamespaceName(self: *ReflectionClass) !*PHPString {
        const full_name = self.class.name.data;
        
        // Find the last backslash for namespace separation
        var last_backslash: ?usize = null;
        for (full_name, 0..) |char, i| {
            if (char == '\\') {
                last_backslash = i;
            }
        }
        
        const namespace_name = if (last_backslash) |pos| 
            full_name[0..pos] 
        else 
            "";
            
        return PHPString.init(self.allocator, namespace_name);
    }
    
    pub fn getMethods(self: *ReflectionClass) ![]ReflectionMethod {
        var methods = std.ArrayList(ReflectionMethod){};
        defer methods.deinit(self.allocator);
        
        // Get methods from this class
        var iterator = self.class.methods.iterator();
        while (iterator.next()) |entry| {
            const method = ReflectionMethod.init(self.allocator, entry.value_ptr, self.class);
            try methods.append(self.allocator, method);
        }
        
        // Get methods from parent classes
        var current_class = self.class.parent;
        while (current_class) |parent| {
            var parent_iterator = parent.methods.iterator();
            while (parent_iterator.next()) |entry| {
                // Check if method is not private (private methods are not inherited)
                const method_def = entry.value_ptr.*;
                if (method_def.modifiers.visibility != .private) {
                    const method = ReflectionMethod.init(self.allocator, entry.value_ptr, parent);
                    try methods.append(self.allocator, method);
                }
            }
            current_class = parent.parent;
        }
        
        // Get methods from traits
        for (self.class.traits) |trait| {
            var trait_iterator = trait.methods.iterator();
            while (trait_iterator.next()) |entry| {
                const method = ReflectionMethod.init(self.allocator, entry.value_ptr, self.class);
                try methods.append(self.allocator, method);
            }
        }
        
        return methods.toOwnedSlice(self.allocator);
    }
    
    pub fn getMethod(self: *const ReflectionClass, name: []const u8) !ReflectionMethod {
        if (self.class.getMethod(name)) |method_def| {
            return ReflectionMethod.init(self.allocator, method_def, self.class);
        }
        return error.MethodNotFound;
    }
    
    pub fn hasMethod(self: *const ReflectionClass, name: []const u8) bool {
        return self.class.hasMethod(name);
    }
    
    pub fn getProperties(self: *ReflectionClass) ![]ReflectionProperty {
        var properties = std.ArrayList(ReflectionProperty){};
        defer properties.deinit(self.allocator);
        
        // Get properties from this class
        var iterator = self.class.properties.iterator();
        while (iterator.next()) |entry| {
            const property = ReflectionProperty.init(self.allocator, entry.value_ptr, self.class);
            try properties.append(self.allocator, property);
        }
        
        // Get properties from parent classes
        var current_class = self.class.parent;
        while (current_class) |parent| {
            var parent_iterator = parent.properties.iterator();
            while (parent_iterator.next()) |entry| {
                // Check if property is not private (private properties are not inherited)
                const property_def = entry.value_ptr.*;
                if (property_def.modifiers.visibility != .private) {
                    const property = ReflectionProperty.init(self.allocator, entry.value_ptr, parent);
                    try properties.append(self.allocator, property);
                }
            }
            current_class = parent.parent;
        }
        
        // Get properties from traits
        for (self.class.traits) |trait| {
            var trait_iterator = trait.properties.iterator();
            while (trait_iterator.next()) |entry| {
                const property = ReflectionProperty.init(self.allocator, entry.value_ptr, self.class);
                try properties.append(self.allocator, property);
            }
        }
        
        return properties.toOwnedSlice(self.allocator);
    }
    
    pub fn getProperty(self: *const ReflectionClass, name: []const u8) !ReflectionProperty {
        if (self.class.getProperty(name)) |property_def| {
            return ReflectionProperty.init(self.allocator, property_def, self.class);
        }
        return error.PropertyNotFound;
    }
    
    pub fn hasProperty(self: *const ReflectionClass, name: []const u8) bool {
        return self.class.hasProperty(name);
    }
    
    pub fn getConstants(self: *ReflectionClass) !std.StringHashMap(Value) {
        var constants = std.StringHashMap(Value).init(self.allocator);
        
        // Get constants from this class
        var iterator = self.class.constants.iterator();
        while (iterator.next()) |entry| {
            try constants.put(entry.key_ptr.*, entry.value_ptr.*);
        }
        
        // Get constants from parent classes
        var current_class = self.class.parent;
        while (current_class) |parent| {
            var parent_iterator = parent.constants.iterator();
            while (parent_iterator.next()) |entry| {
                // Only add if not already defined in child class
                if (!constants.contains(entry.key_ptr.*)) {
                    try constants.put(entry.key_ptr.*, entry.value_ptr.*);
                }
            }
            current_class = parent.parent;
        }
        
        return constants;
    }
    
    pub fn getConstant(self: *ReflectionClass, name: []const u8) ?Value {
        // Check this class first
        if (self.class.constants.get(name)) |value| {
            return value;
        }
        
        // Check parent classes
        var current_class = self.class.parent;
        while (current_class) |parent| {
            if (parent.constants.get(name)) |value| {
                return value;
            }
            current_class = parent.parent;
        }
        
        return null;
    }
    
    pub fn hasConstant(self: *ReflectionClass, name: []const u8) bool {
        return self.getConstant(name) != null;
    }
    
    pub fn newInstance(self: *ReflectionClass, vm: *VM, args: []const Value) !*PHPObject {
        // Check if class is abstract
        if (self.class.modifiers.is_abstract) {
            return error.CannotInstantiateAbstractClass;
        }
        
        const object = try self.allocator.create(PHPObject);
        object.* = PHPObject.init(self.allocator, self.class);
        
        // Initialize properties with default values
        var prop_iterator = self.class.properties.iterator();
        while (prop_iterator.next()) |entry| {
            const property = entry.value_ptr.*;
            if (property.default_value) |default_val| {
                try object.setProperty(entry.key_ptr.*, default_val);
            }
        }
        
        // Call constructor if it exists
        if (self.class.hasMethod("__construct")) {
            _ = try object.callMethod(vm, "__construct", args);
        }
        
        return object;
    }
    
    pub fn newInstanceArgs(self: *ReflectionClass, vm: *VM, args: []const Value) !*PHPObject {
        return self.newInstance(vm, args);
    }
    
    pub fn newInstanceWithoutConstructor(self: *ReflectionClass) !*PHPObject {
        // Check if class is abstract
        if (self.class.modifiers.is_abstract) {
            return error.CannotInstantiateAbstractClass;
        }
        
        const object = try self.allocator.create(PHPObject);
        object.* = PHPObject.init(self.allocator, self.class);
        
        // Initialize properties with default values but don't call constructor
        var prop_iterator = self.class.properties.iterator();
        while (prop_iterator.next()) |entry| {
            const property = entry.value_ptr.*;
            if (property.default_value) |default_val| {
                try object.setProperty(entry.key_ptr.*, default_val);
            }
        }
        
        return object;
    }
    
    pub fn isAbstract(self: *ReflectionClass) bool {
        return self.class.modifiers.is_abstract;
    }
    
    pub fn isFinal(self: *const ReflectionClass) bool {
        return self.class.modifiers.is_final;
    }
    
    pub fn isReadonly(self: *ReflectionClass) bool {
        return self.class.modifiers.is_readonly;
    }
    
    pub fn isInstantiable(self: *ReflectionClass) bool {
        return !self.class.modifiers.is_abstract;
    }
    
    pub fn isInterface(self: *ReflectionClass) bool {
        // In a full implementation, this would check if the class is actually an interface
        _ = self;
        return false; // Simplified for now
    }
    
    pub fn isTrait(self: *ReflectionClass) bool {
        // In a full implementation, this would check if the class is actually a trait
        _ = self;
        return false; // Simplified for now
    }
    
    pub fn isSubclassOf(self: *const ReflectionClass, other: *const ReflectionClass) bool {
        return self.class.isInstanceOf(other.class);
    }
    
    pub fn implementsInterface(self: *ReflectionClass, interface: *types.PHPInterface) bool {
        return self.class.implementsInterface(interface);
    }
    
    pub fn getParentClass(self: *ReflectionClass) ?ReflectionClass {
        if (self.class.parent) |parent| {
            return ReflectionClass.init(self.allocator, parent);
        }
        return null;
    }
    
    pub fn getInterfaces(self: *ReflectionClass) []const *types.PHPInterface {
        return self.class.interfaces;
    }
    
    pub fn getTraits(self: *ReflectionClass) []const *types.PHPTrait {
        return self.class.traits;
    }
    
    pub fn getAttributes(self: *const ReflectionClass, filter_class: ?[]const u8) ![]types.Attribute {
        if (filter_class) |filter| {
            // Count matching attributes first
            var count: usize = 0;
            for (self.class.attributes) |attr| {
                if (std.mem.eql(u8, attr.name.data, filter)) {
                    count += 1;
                }
            }
            
            // Allocate and fill result array
            var result = try self.allocator.alloc(types.Attribute, count);
            var index: usize = 0;
            for (self.class.attributes) |attr| {
                if (std.mem.eql(u8, attr.name.data, filter)) {
                    result[index] = attr;
                    index += 1;
                }
            }
            
            return result;
        }
        
        return try self.allocator.dupe(types.Attribute, self.class.attributes);
    }
    
    pub fn getAttributeInstances(self: *const ReflectionClass, filter_class: ?[]const u8) ![]Value {
        const attributes = try self.getAttributes(filter_class);
        defer self.allocator.free(attributes);
        
        var instances = std.ArrayList(Value){};
        defer instances.deinit(self.allocator);
        
        for (attributes) |attr| {
            const instance = try attr.instantiate(self.allocator);
            const object_value = try Value.initObject(self.allocator, instance.class);
            try instances.append(self.allocator, object_value);
        }
        
        return instances.toOwnedSlice(self.allocator);
    }
    
    pub fn hasAttribute(self: *const ReflectionClass, attribute_name: []const u8) bool {
        for (self.class.attributes) |attr| {
            if (std.mem.eql(u8, attr.name.data, attribute_name)) {
                return true;
            }
        }
        return false;
    }
    
    pub fn getConstructor(self: *ReflectionClass) ?ReflectionMethod {
        if (self.class.getMethod("__construct")) |method| {
            return ReflectionMethod.init(self.allocator, &method, self.class);
        }
        return null;
    }
    
    pub fn getDestructor(self: *ReflectionClass) ?ReflectionMethod {
        if (self.class.getMethod("__destruct")) |method| {
            return ReflectionMethod.init(self.allocator, &method, self.class);
        }
        return null;
    }
};

/// ReflectionMethod provides runtime introspection of PHP methods
pub const ReflectionMethod = struct {
    method: *Method,
    declaring_class: *PHPClass,
    allocator: std.mem.Allocator,
    
    pub fn init(allocator: std.mem.Allocator, method: *Method, declaring_class: *PHPClass) ReflectionMethod {
        return ReflectionMethod{
            .method = method,
            .declaring_class = declaring_class,
            .allocator = allocator,
        };
    }
    
    pub fn getName(self: *const ReflectionMethod) *PHPString {
        return self.method.name;
    }
    
    pub fn getDeclaringClass(self: *ReflectionMethod) ReflectionClass {
        return ReflectionClass.init(self.allocator, self.declaring_class);
    }
    
    pub fn invoke(self: *ReflectionMethod, vm: *VM, object: ?*PHPObject, args: []const Value) !Value {
        if (self.method.modifiers.is_static) {
            // Static method call - object should be null
            if (object != null) {
                return error.StaticMethodCalledOnInstance;
            }
            // For now, return null - actual static method execution would happen here
            // In a real implementation, this would execute the static method using vm and args
            return Value.initNull();
        }
        
        // Instance method call - object is required
        const obj = object orelse {
            return error.InstanceMethodCalledWithoutObject;
        };
        return obj.callMethod(vm, self.method.name.data, args);
    }
    
    pub fn invokeArgs(self: *ReflectionMethod, vm: *VM, object: ?*PHPObject, args: []const Value) !Value {
        return self.invoke(vm, object, args);
    }
    
    pub fn getParameters(self: *const ReflectionMethod) ![]ReflectionParameter {
        var parameters = try self.allocator.alloc(ReflectionParameter, self.method.parameters.len);
        
        for (self.method.parameters, 0..) |_, i| {
            parameters[i] = ReflectionParameter.init(self.allocator, &self.method.parameters[i], self.method, @intCast(i));
        }
        
        return parameters;
    }
    
    pub fn getNumberOfParameters(self: *const ReflectionMethod) usize {
        return self.method.parameters.len;
    }
    
    pub fn getNumberOfRequiredParameters(self: *const ReflectionMethod) usize {
        var count: usize = 0;
        for (self.method.parameters) |param| {
            if (param.default_value == null and !param.is_variadic) {
                count += 1;
            }
        }
        return count;
    }
    
    pub fn getReturnType(self: *ReflectionMethod) ?ReflectionType {
        if (self.method.return_type) |return_type| {
            return ReflectionType.init(self.allocator, &return_type);
        }
        return null;
    }
    
    pub fn hasReturnType(self: *ReflectionMethod) bool {
        return self.method.return_type != null;
    }
    
    pub fn isPublic(self: *const ReflectionMethod) bool {
        return self.method.modifiers.visibility == .public;
    }
    
    pub fn isProtected(self: *const ReflectionMethod) bool {
        return self.method.modifiers.visibility == .protected;
    }
    
    pub fn isPrivate(self: *const ReflectionMethod) bool {
        return self.method.modifiers.visibility == .private;
    }
    
    pub fn isStatic(self: *const ReflectionMethod) bool {
        return self.method.modifiers.is_static;
    }
    
    pub fn isFinal(self: *const ReflectionMethod) bool {
        return self.method.modifiers.is_final;
    }
    
    pub fn isAbstract(self: *const ReflectionMethod) bool {
        return self.method.modifiers.is_abstract;
    }
    
    pub fn isConstructor(self: *const ReflectionMethod) bool {
        return self.method.isConstructor();
    }
    
    pub fn isDestructor(self: *const ReflectionMethod) bool {
        return self.method.isDestructor();
    }
    
    pub fn isMagic(self: *const ReflectionMethod) bool {
        return self.method.isMagicMethod();
    }
    
    pub fn getAttributes(self: *const ReflectionMethod, filter_class: ?[]const u8) ![]types.Attribute {
        if (filter_class) |filter| {
            // Count matching attributes first
            var count: usize = 0;
            for (self.method.attributes) |attr| {
                if (std.mem.eql(u8, attr.name.data, filter)) {
                    count += 1;
                }
            }
            
            // Allocate and fill result array
            var result = try self.allocator.alloc(types.Attribute, count);
            var index: usize = 0;
            for (self.method.attributes) |attr| {
                if (std.mem.eql(u8, attr.name.data, filter)) {
                    result[index] = attr;
                    index += 1;
                }
            }
            
            return result;
        }
        
        return try self.allocator.dupe(types.Attribute, self.method.attributes);
    }
    
    pub fn getAttributeInstances(self: *const ReflectionMethod, filter_class: ?[]const u8) ![]Value {
        const attributes = try self.getAttributes(filter_class);
        defer self.allocator.free(attributes);
        
        var instances = std.ArrayList(Value){};
        defer instances.deinit(self.allocator);
        
        for (attributes) |attr| {
            const instance = try attr.instantiate(self.allocator);
            const object_value = try Value.initObject(self.allocator, instance.class);
            try instances.append(self.allocator, object_value);
        }
        
        return instances.toOwnedSlice(self.allocator);
    }
    
    pub fn hasAttribute(self: *const ReflectionMethod, attribute_name: []const u8) bool {
        for (self.method.attributes) |attr| {
            if (std.mem.eql(u8, attr.name.data, attribute_name)) {
                return true;
            }
        }
        return false;
    }
    
    pub fn getClosure(self: *ReflectionMethod, vm: *VM, object: ?*PHPObject) !Value {
        // Create a closure that binds this method to the object
        const function_name = try PHPString.init(self.allocator, self.method.name.data);
        var user_function = UserFunction.init(function_name);
        user_function.parameters = self.method.parameters;
        user_function.return_type = self.method.return_type;
        user_function.body = self.method.body;
        
        var closure = types.Closure.init(self.allocator, user_function);
        
        // Bind $this if object is provided
        if (object) |obj| {
            const this_value = Value{ .tag = .object, .data = .{ .object = undefined } }; // Would be properly set
            try closure.captureVariable("this", this_value);
            _ = obj; // Use obj to create proper binding
        }
        
        const box = try self.allocator.create(gc.Box(*types.Closure));
        box.* = .{
            .ref_count = 1,
            .gc_info = .{},
            .data = try self.allocator.create(types.Closure),
        };
        box.data.* = closure;
        
        _ = vm; // Would be used for proper closure creation
        return Value{ .tag = .closure, .data = .{ .closure = box } };
    }
};

/// ReflectionProperty provides runtime introspection of PHP properties
pub const ReflectionProperty = struct {
    property: *Property,
    declaring_class: *PHPClass,
    allocator: std.mem.Allocator,
    
    pub fn init(allocator: std.mem.Allocator, property: *Property, declaring_class: *PHPClass) ReflectionProperty {
        return ReflectionProperty{
            .property = property,
            .declaring_class = declaring_class,
            .allocator = allocator,
        };
    }
    
    pub fn getName(self: *const ReflectionProperty) *PHPString {
        return self.property.name;
    }
    
    pub fn getDeclaringClass(self: *ReflectionProperty) ReflectionClass {
        return ReflectionClass.init(self.allocator, self.declaring_class);
    }
    
    pub fn getValue(self: *ReflectionProperty, object: ?*PHPObject) !Value {
        if (self.property.modifiers.is_static) {
            // Static property - get from class
            return self.property.default_value orelse Value.initNull();
        } else {
            // Instance property - get from object
            const obj = object orelse {
                return error.InstancePropertyAccessedWithoutObject;
            };
            return obj.getProperty(self.property.name.data);
        }
    }
    
    pub fn setValue(self: *ReflectionProperty, object: ?*PHPObject, value: Value) !void {
        if (self.property.modifiers.is_static) {
            // Static property - would set on class
            // For now, just validate that object is null
            if (object != null) {
                return error.StaticPropertySetOnInstance;
            }
            // In a real implementation, would set the static property value
        } else {
            // Instance property - set on object
            const obj = object orelse {
                return error.InstancePropertySetWithoutObject;
            };
            try obj.setProperty(self.property.name.data, value);
        }
    }
    
    pub fn isInitialized(self: *ReflectionProperty, object: ?*PHPObject) bool {
        if (self.property.modifiers.is_static) {
            return self.property.default_value != null;
        } else {
            const obj = object orelse return false;
            return obj.properties.contains(self.property.name.data);
        }
    }
    
    pub fn getDefaultValue(self: *const ReflectionProperty) ?Value {
        return self.property.default_value;
    }
    
    pub fn hasDefaultValue(self: *const ReflectionProperty) bool {
        return self.property.default_value != null;
    }
    
    pub fn getType(self: *ReflectionProperty) ?ReflectionType {
        if (self.property.type) |prop_type| {
            return ReflectionType.init(self.allocator, &prop_type);
        }
        return null;
    }
    
    pub fn hasType(self: *ReflectionProperty) bool {
        return self.property.type != null;
    }
    
    pub fn isPublic(self: *const ReflectionProperty) bool {
        return self.property.modifiers.visibility == .public;
    }
    
    pub fn isProtected(self: *const ReflectionProperty) bool {
        return self.property.modifiers.visibility == .protected;
    }
    
    pub fn isPrivate(self: *const ReflectionProperty) bool {
        return self.property.modifiers.visibility == .private;
    }
    
    pub fn isStatic(self: *const ReflectionProperty) bool {
        return self.property.modifiers.is_static;
    }
    
    pub fn isReadonly(self: *const ReflectionProperty) bool {
        return self.property.modifiers.is_readonly;
    }
    
    pub fn getAttributes(self: *const ReflectionProperty, filter_class: ?[]const u8) ![]types.Attribute {
        if (filter_class) |filter| {
            // Count matching attributes first
            var count: usize = 0;
            for (self.property.attributes) |attr| {
                if (std.mem.eql(u8, attr.name.data, filter)) {
                    count += 1;
                }
            }
            
            // Allocate and fill result array
            var result = try self.allocator.alloc(types.Attribute, count);
            var index: usize = 0;
            for (self.property.attributes) |attr| {
                if (std.mem.eql(u8, attr.name.data, filter)) {
                    result[index] = attr;
                    index += 1;
                }
            }
            
            return result;
        }
        
        return try self.allocator.dupe(types.Attribute, self.property.attributes);
    }
    
    pub fn getAttributeInstances(self: *const ReflectionProperty, filter_class: ?[]const u8) ![]Value {
        const attributes = try self.getAttributes(filter_class);
        defer self.allocator.free(attributes);
        
        var instances = std.ArrayList(Value){};
        defer instances.deinit(self.allocator);
        
        for (attributes) |attr| {
            const instance = try attr.instantiate(self.allocator);
            const object_value = try Value.initObject(self.allocator, instance.class);
            try instances.append(self.allocator, object_value);
        }
        
        return instances.toOwnedSlice(self.allocator);
    }
    
    pub fn hasAttribute(self: *const ReflectionProperty, attribute_name: []const u8) bool {
        for (self.property.attributes) |attr| {
            if (std.mem.eql(u8, attr.name.data, attribute_name)) {
                return true;
            }
        }
        return false;
    }
    
    pub fn hasHooks(self: *ReflectionProperty) bool {
        return self.property.hooks.len > 0;
    }
    
    pub fn hasGetHook(self: *ReflectionProperty) bool {
        return self.property.hasGetHook();
    }
    
    pub fn hasSetHook(self: *ReflectionProperty) bool {
        return self.property.hasSetHook();
    }
    
    pub fn getHooks(self: *ReflectionProperty) []const types.PropertyHook {
        return self.property.hooks;
    }
};

/// ReflectionParameter provides runtime introspection of PHP function/method parameters
pub const ReflectionParameter = struct {
    parameter: *const Method.Parameter,
    declaring_function: *const Method,
    position: u32,
    allocator: std.mem.Allocator,
    
    pub fn init(allocator: std.mem.Allocator, parameter: *const Method.Parameter, declaring_function: *const Method, position: u32) ReflectionParameter {
        return ReflectionParameter{
            .parameter = parameter,
            .declaring_function = declaring_function,
            .position = position,
            .allocator = allocator,
        };
    }
    
    pub fn getName(self: *ReflectionParameter) *PHPString {
        return self.parameter.name;
    }
    
    pub fn getPosition(self: *ReflectionParameter) u32 {
        return self.position;
    }
    
    pub fn getType(self: *ReflectionParameter) ?ReflectionType {
        if (self.parameter.type) |param_type| {
            return ReflectionType.init(self.allocator, &param_type);
        }
        return null;
    }
    
    pub fn hasType(self: *ReflectionParameter) bool {
        return self.parameter.type != null;
    }
    
    pub fn allowsNull(self: *ReflectionParameter) bool {
        if (self.parameter.type) |param_type| {
            return param_type.is_nullable;
        }
        return true; // No type constraint means null is allowed
    }
    
    pub fn getDefaultValue(self: *ReflectionParameter) ?Value {
        return self.parameter.default_value;
    }
    
    pub fn hasDefaultValue(self: *ReflectionParameter) bool {
        return self.parameter.default_value != null;
    }
    
    pub fn isDefaultValueAvailable(self: *ReflectionParameter) bool {
        return self.hasDefaultValue();
    }
    
    pub fn isOptional(self: *ReflectionParameter) bool {
        return self.hasDefaultValue() or self.parameter.is_variadic;
    }
    
    pub fn isVariadic(self: *ReflectionParameter) bool {
        return self.parameter.is_variadic;
    }
    
    pub fn isPassedByReference(self: *ReflectionParameter) bool {
        return self.parameter.is_reference;
    }
    
    pub fn isPromoted(self: *ReflectionParameter) bool {
        return self.parameter.is_promoted;
    }
    
    pub fn getAttributes(self: *const ReflectionParameter, filter_class: ?[]const u8) ![]types.Attribute {
        if (filter_class) |filter| {
            // Count matching attributes first
            var count: usize = 0;
            for (self.parameter.attributes) |attr| {
                if (std.mem.eql(u8, attr.name.data, filter)) {
                    count += 1;
                }
            }
            
            // Allocate and fill result array
            var result = try self.allocator.alloc(types.Attribute, count);
            var index: usize = 0;
            for (self.parameter.attributes) |attr| {
                if (std.mem.eql(u8, attr.name.data, filter)) {
                    result[index] = attr;
                    index += 1;
                }
            }
            
            return result;
        }
        
        return try self.allocator.dupe(types.Attribute, self.parameter.attributes);
    }
    
    pub fn getAttributeInstances(self: *const ReflectionParameter, filter_class: ?[]const u8) ![]Value {
        const attributes = try self.getAttributes(filter_class);
        defer self.allocator.free(attributes);
        
        var instances = std.ArrayList(Value){};
        defer instances.deinit(self.allocator);
        
        for (attributes) |attr| {
            const instance = try attr.instantiate(self.allocator);
            const object_value = try Value.initObject(self.allocator, instance.class);
            try instances.append(self.allocator, object_value);
        }
        
        return instances.toOwnedSlice(self.allocator);
    }
    
    pub fn hasAttribute(self: *const ReflectionParameter, attribute_name: []const u8) bool {
        for (self.parameter.attributes) |attr| {
            if (std.mem.eql(u8, attr.name.data, attribute_name)) {
                return true;
            }
        }
        return false;
    }
};

/// ReflectionFunction provides runtime introspection of PHP functions
pub const ReflectionFunction = struct {
    function: *UserFunction,
    allocator: std.mem.Allocator,
    
    pub fn init(allocator: std.mem.Allocator, function: *UserFunction) ReflectionFunction {
        return ReflectionFunction{
            .function = function,
            .allocator = allocator,
        };
    }
    
    pub fn getName(self: *ReflectionFunction) *PHPString {
        return self.function.name;
    }
    
    pub fn invoke(self: *ReflectionFunction, vm: *VM, args: []const Value) !Value {
        return vm.callUserFunction(self.function, args);
    }
    
    pub fn invokeArgs(self: *ReflectionFunction, vm: *VM, args: []const Value) !Value {
        return self.invoke(vm, args);
    }
    
    pub fn getParameters(self: *ReflectionFunction) ![]ReflectionParameter {
        var parameters = try self.allocator.alloc(ReflectionParameter, self.function.parameters.len);
        
        // Create a dummy method for the parameter reflection
        const dummy_method = Method{
            .name = self.function.name,
            .parameters = self.function.parameters,
            .return_type = self.function.return_type,
            .modifiers = .{},
            .attributes = self.function.attributes,
            .body = self.function.body,
        };
        
        for (self.function.parameters, 0..) |param, i| {
            parameters[i] = ReflectionParameter.init(self.allocator, &param, &dummy_method, @intCast(i));
        }
        
        return parameters;
    }
    
    pub fn getNumberOfParameters(self: *ReflectionFunction) usize {
        return self.function.parameters.len;
    }
    
    pub fn getNumberOfRequiredParameters(self: *ReflectionFunction) usize {
        var count: usize = 0;
        for (self.function.parameters) |param| {
            if (param.default_value == null and !param.is_variadic) {
                count += 1;
            }
        }
        return count;
    }
    
    pub fn getReturnType(self: *ReflectionFunction) ?ReflectionType {
        if (self.function.return_type) |return_type| {
            return ReflectionType.init(self.allocator, &return_type);
        }
        return null;
    }
    
    pub fn hasReturnType(self: *ReflectionFunction) bool {
        return self.function.return_type != null;
    }
    
    pub fn isVariadic(self: *ReflectionFunction) bool {
        return self.function.is_variadic;
    }
    
    pub fn getAttributes(self: *const ReflectionFunction, filter_class: ?[]const u8) ![]types.Attribute {
        if (filter_class) |filter| {
            // Count matching attributes first
            var count: usize = 0;
            for (self.function.attributes) |attr| {
                if (std.mem.eql(u8, attr.name.data, filter)) {
                    count += 1;
                }
            }
            
            // Allocate and fill result array
            var result = try self.allocator.alloc(types.Attribute, count);
            var index: usize = 0;
            for (self.function.attributes) |attr| {
                if (std.mem.eql(u8, attr.name.data, filter)) {
                    result[index] = attr;
                    index += 1;
                }
            }
            
            return result;
        }
        
        return try self.allocator.dupe(types.Attribute, self.function.attributes);
    }
    
    pub fn getAttributeInstances(self: *const ReflectionFunction, filter_class: ?[]const u8) ![]Value {
        const attributes = try self.getAttributes(filter_class);
        defer self.allocator.free(attributes);
        
        var instances = std.ArrayList(Value){};
        defer instances.deinit(self.allocator);
        
        for (attributes) |attr| {
            const instance = try attr.instantiate(self.allocator);
            const object_value = try Value.initObject(self.allocator, instance.class);
            try instances.append(self.allocator, object_value);
        }
        
        return instances.toOwnedSlice(self.allocator);
    }
    
    pub fn hasAttribute(self: *const ReflectionFunction, attribute_name: []const u8) bool {
        for (self.function.attributes) |attr| {
            if (std.mem.eql(u8, attr.name.data, attribute_name)) {
                return true;
            }
        }
        return false;
    }
    
    pub fn getClosure(self: *ReflectionFunction, vm: *VM) !Value {
        const closure = types.Closure.init(self.allocator, self.function.*);
        
        const box = try self.allocator.create(gc.Box(*types.Closure));
        box.* = .{
            .ref_count = 1,
            .gc_info = .{},
            .data = try self.allocator.create(types.Closure),
        };
        box.data.* = closure;
        
        _ = vm; // Would be used for proper closure creation
        return Value{ .tag = .closure, .data = .{ .closure = box } };
    }
};

/// ReflectionType provides runtime introspection of PHP types
pub const ReflectionType = struct {
    type_info: *const types.TypeInfo,
    allocator: std.mem.Allocator,
    
    pub fn init(allocator: std.mem.Allocator, type_info: *const types.TypeInfo) ReflectionType {
        return ReflectionType{
            .type_info = type_info,
            .allocator = allocator,
        };
    }
    
    pub fn getName(self: *const ReflectionType) *PHPString {
        return self.type_info.name;
    }
    
    pub fn allowsNull(self: *const ReflectionType) bool {
        return self.type_info.is_nullable;
    }
    
    pub fn isBuiltin(self: *const ReflectionType) bool {
        const type_name = self.type_info.name.data;
        const builtin_types = [_][]const u8{
            "null", "bool", "boolean", "int", "integer", 
            "float", "double", "string", "array", "object", 
            "resource", "callable", "mixed", "void"
        };
        
        for (builtin_types) |builtin| {
            if (std.mem.eql(u8, type_name, builtin)) {
                return true;
            }
        }
        return false;
    }
    
    pub fn toString(self: *const ReflectionType, allocator: std.mem.Allocator) !*PHPString {
        var type_str = std.ArrayList(u8){};
        defer type_str.deinit(allocator);
        
        if (self.type_info.is_nullable) {
            try type_str.append(allocator, '?');
        }
        
        if (self.type_info.is_union) {
            for (self.type_info.union_types, 0..) |union_type, i| {
                if (i > 0) {
                    try type_str.appendSlice(allocator, "|");
                }
                try type_str.appendSlice(allocator, union_type.name.data);
            }
        } else {
            try type_str.appendSlice(allocator, self.type_info.name.data);
        }
        
        return PHPString.init(allocator, type_str.items);
    }
};

/// ReflectionObject provides runtime introspection of PHP object instances
pub const ReflectionObject = struct {
    object: *PHPObject,
    allocator: std.mem.Allocator,
    
    pub fn init(allocator: std.mem.Allocator, object: *PHPObject) ReflectionObject {
        return ReflectionObject{
            .object = object,
            .allocator = allocator,
        };
    }
    
    pub fn getClass(self: *ReflectionObject) ReflectionClass {
        return ReflectionClass.init(self.allocator, self.object.class);
    }
    
    pub fn getClassName(self: *const ReflectionObject) *PHPString {
        return self.object.class.name;
    }
    
    pub fn hasProperty(self: *const ReflectionObject, name: []const u8) bool {
        return self.object.properties.contains(name) or self.object.class.hasProperty(name);
    }
    
    pub fn getProperties(self: *ReflectionObject) ![]Value {
        var properties = std.ArrayList(Value){};
        defer properties.deinit(self.allocator);
        
        var iterator = self.object.properties.iterator();
        while (iterator.next()) |entry| {
            try properties.append(self.allocator, entry.value_ptr.*);
        }
        
        return properties.toOwnedSlice(self.allocator);
    }
    
    pub fn getPropertyNames(self: *const ReflectionObject) ![][]const u8 {
        var names = std.ArrayList([]const u8){};
        defer names.deinit(self.allocator);
        
        var iterator = self.object.properties.iterator();
        while (iterator.next()) |entry| {
            try names.append(self.allocator, entry.key_ptr.*);
        }
        
        return names.toOwnedSlice(self.allocator);
    }
};

/// ReflectionAttribute provides runtime introspection of PHP attributes
pub const ReflectionAttribute = struct {
    attribute: *const types.Attribute,
    allocator: std.mem.Allocator,
    
    pub fn init(allocator: std.mem.Allocator, attribute: *const types.Attribute) ReflectionAttribute {
        return ReflectionAttribute{
            .attribute = attribute,
            .allocator = allocator,
        };
    }
    
    pub fn getName(self: *const ReflectionAttribute) *PHPString {
        return self.attribute.name;
    }
    
    pub fn getArguments(self: *const ReflectionAttribute) []const Value {
        return self.attribute.arguments;
    }
    
    pub fn getTarget(self: *const ReflectionAttribute) types.Attribute.AttributeTarget {
        return self.attribute.target;
    }
    
    pub fn canBeAppliedTo(self: *const ReflectionAttribute, target_type: types.Attribute.AttributeTargetType) bool {
        return self.attribute.canBeAppliedTo(target_type);
    }
    
    pub fn newInstance(self: *const ReflectionAttribute) !*PHPObject {
        return self.attribute.instantiate(self.allocator);
    }
    
    pub fn isRepeated(self: *const ReflectionAttribute) bool {
        // In a full implementation, this would check if the attribute is marked as repeatable
        _ = self;
        return false; // Simplified for now
    }
    
    pub fn getFlags(self: *const ReflectionAttribute) u32 {
        // Convert AttributeTarget to flags
        var flags: u32 = 0;
        if (self.attribute.target.class) flags |= 0x01;
        if (self.attribute.target.method) flags |= 0x02;
        if (self.attribute.target.property) flags |= 0x04;
        if (self.attribute.target.parameter) flags |= 0x08;
        if (self.attribute.target.function) flags |= 0x10;
        if (self.attribute.target.constant) flags |= 0x20;
        if (self.attribute.target.all) flags |= 0xFF;
        return flags;
    }
};

/// Main reflection system that provides factory methods for creating reflection objects
pub const ReflectionSystem = struct {
    allocator: std.mem.Allocator,
    vm: *VM,
    
    pub fn init(allocator: std.mem.Allocator, vm: *VM) ReflectionSystem {
        return ReflectionSystem{
            .allocator = allocator,
            .vm = vm,
        };
    }
    
    pub fn getClass(self: *ReflectionSystem, name: []const u8) !ReflectionClass {
        const class = self.vm.getClass(name) orelse {
            return error.ClassNotFound;
        };
        return ReflectionClass.init(self.allocator, class);
    }
    
    pub fn getClassFromObject(self: *ReflectionSystem, object: *PHPObject) ReflectionClass {
        return ReflectionClass.init(self.allocator, object.class);
    }
    
    pub fn getObject(self: *ReflectionSystem, object: *PHPObject) ReflectionObject {
        return ReflectionObject.init(self.allocator, object);
    }
    
    pub fn getFunction(self: *ReflectionSystem, name: []const u8) !ReflectionFunction {
        const function_val = self.vm.global.get(name) orelse {
            return error.FunctionNotFound;
        };
        
        if (function_val.tag != .user_function) {
            return error.NotAUserFunction;
        }
        
        return ReflectionFunction.init(self.allocator, function_val.data.user_function.data);
    }
    
    pub fn getMethod(self: *ReflectionSystem, class_name: []const u8, method_name: []const u8) !ReflectionMethod {
        const reflection_class = try self.getClass(class_name);
        return reflection_class.getMethod(method_name);
    }
    
    pub fn getProperty(self: *ReflectionSystem, class_name: []const u8, property_name: []const u8) !ReflectionProperty {
        const reflection_class = try self.getClass(class_name);
        return reflection_class.getProperty(property_name);
    }
    
    pub fn getAttribute(self: *ReflectionSystem, attribute: *const types.Attribute) ReflectionAttribute {
        return ReflectionAttribute.init(self.allocator, attribute);
    }
    
    pub fn createAttributeClass(self: *ReflectionSystem, name: []const u8, target: types.Attribute.AttributeTarget) !*PHPClass {
        const class_name = try PHPString.init(self.allocator, name);
        var attribute_class = PHPClass.init(self.allocator, class_name);
        
        // Mark as attribute class
        attribute_class.modifiers.is_final = true; // Attributes are typically final
        
        // Add target information as a property
        const target_property_name = try PHPString.init(self.allocator, "target");
        var target_property = Property.init(target_property_name);
        target_property.modifiers.visibility = .public;
        target_property.modifiers.is_readonly = true;
        
        // Convert target to integer value for storage
        var target_value: u32 = 0;
        if (target.class) target_value |= 0x01;
        if (target.method) target_value |= 0x02;
        if (target.property) target_value |= 0x04;
        if (target.parameter) target_value |= 0x08;
        if (target.function) target_value |= 0x10;
        if (target.constant) target_value |= 0x20;
        if (target.all) target_value |= 0xFF;
        
        target_property.default_value = Value.initInt(@intCast(target_value));
        try attribute_class.properties.put("target", target_property);
        
        const class_ptr = try self.allocator.create(PHPClass);
        class_ptr.* = attribute_class;
        
        // Register the attribute class with the VM
        try self.vm.defineClass(name, class_ptr);
        
        return class_ptr;
    }
};