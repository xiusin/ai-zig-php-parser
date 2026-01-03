/// Configuration module for zig-php
/// Provides configuration file loading and merging functionality

pub const loader = @import("loader.zig");
pub const Config = loader.Config;
pub const ConfigLoader = loader.ConfigLoader;
pub const MergedConfig = loader.MergedConfig;
