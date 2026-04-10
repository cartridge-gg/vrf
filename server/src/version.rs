use std::fmt::Write;

/// The latest version from Cargo.toml.
const CARGO_PKG_VERSION: &str = env!("CARGO_PKG_VERSION");

/// Suffix indicating if it is a dev build.
///
/// A build is considered a dev build if the working tree is dirty
/// or if the current git revision is not on a tag.
///
/// This suffix is typically empty for clean/release builds, and "-dev" for dev builds.
const DEV_BUILD_SUFFIX: &str = env!("DEV_BUILD_SUFFIX");

/// The SHA of the latest commit.
const VERGEN_GIT_SHA: &str = env!("VERGEN_GIT_SHA");

/// The build timestamp.
const VERGEN_BUILD_TIMESTAMP: &str = env!("VERGEN_BUILD_TIMESTAMP");

// > 0.1.0 (77d4800)
// > if on dev (ie dirty):  0.1.0-dev (77d4800)
pub fn generate_short() -> &'static str {
    const_format::concatcp!(CARGO_PKG_VERSION, DEV_BUILD_SUFFIX, " (", VERGEN_GIT_SHA, ")")
}

pub fn generate_long() -> String {
    let mut out = String::new();
    writeln!(out, "{}", generate_short()).unwrap();
    writeln!(out).unwrap();
    write!(out, "built on: {VERGEN_BUILD_TIMESTAMP}").unwrap();
    out
}
