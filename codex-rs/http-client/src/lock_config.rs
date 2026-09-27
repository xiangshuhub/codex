//! Fork customization: a single locked configuration for the outbound proxy and
//! the timezone reported to the model.
//!
//! The configuration is read once per process from a small TOML-like file:
//!
//! ```toml
//! # Outbound HTTP proxy. Every non-loopback destination is routed through it;
//! # system proxy settings and HTTP(S)_PROXY/ALL_PROXY environment variables are
//! # ignored while the lock is active.
//! proxy = "http://127.0.0.1:10809"
//!
//! # IANA timezone name sent to the model in the environment context.
//! timezone = "America/Los_Angeles"
//! ```
//!
//! File lookup order: `$CODEX_LOCK_CONFIG`, then `$CODEX_HOME/lock.toml`, then
//! `~/.codex/lock.toml`. A missing file or missing keys fall back to the defaults
//! shown above, so the lock is active even without a file.
//!
//! Setting `CODEX_LOCK_DISABLE=1` turns the lock off and restores upstream
//! proxy behavior. Loopback destinations (localhost/127.0.0.1/::1) never go
//! through the locked proxy so local fixtures and servers keep working.

use std::fs;
use std::path::Path;
use std::path::PathBuf;
use std::sync::OnceLock;

/// Default locked proxy: local HTTP proxy port (v2rayN-style HTTP listener).
pub const DEFAULT_LOCK_PROXY_URL: &str = "http://127.0.0.1:10809";
/// Default locked timezone.
pub const DEFAULT_LOCK_TIMEZONE: &str = "America/Los_Angeles";

const LOCK_FILE_NAME: &str = "lock.toml";

/// Parsed contents of the lock file.
#[derive(Debug, Default, Clone, PartialEq, Eq)]
pub(crate) struct LockConfig {
    pub(crate) proxy_url: Option<String>,
    pub(crate) timezone: Option<String>,
}

impl LockConfig {
    fn proxy_url(&self) -> String {
        self.proxy_url
            .clone()
            .filter(|url| !url.is_empty())
            .unwrap_or_else(|| DEFAULT_LOCK_PROXY_URL.to_string())
    }

    fn timezone(&self) -> String {
        self.timezone
            .clone()
            .filter(|tz| !tz.is_empty())
            .unwrap_or_else(|| DEFAULT_LOCK_TIMEZONE.to_string())
    }
}

/// Returns the locked proxy URL for this process (default when unconfigured).
pub fn locked_proxy_url() -> String {
    static CONFIG: OnceLock<LockConfig> = OnceLock::new();
    CONFIG
        .get_or_init(|| load_lock_config(lock_config_path().as_deref(), |path| {
            fs::read_to_string(path).ok()
        }))
        .proxy_url()
}

/// Returns the locked timezone for this process (default when unconfigured).
pub fn locked_timezone() -> String {
    static CONFIG: OnceLock<LockConfig> = OnceLock::new();
    CONFIG
        .get_or_init(|| load_lock_config(lock_config_path().as_deref(), |path| {
            fs::read_to_string(path).ok()
        }))
        .timezone()
}

/// Whether the fork lock was disabled via `CODEX_LOCK_DISABLE`.
pub(crate) fn lock_disabled() -> bool {
    static DISABLED: OnceLock<bool> = OnceLock::new();
    *DISABLED.get_or_init(|| {
        matches!(
            std::env::var("CODEX_LOCK_DISABLE").as_deref(),
            Ok("1" | "true" | "yes")
        )
    })
}

fn lock_config_path() -> Option<PathBuf> {
    if let Some(path) = std::env::var_os("CODEX_LOCK_CONFIG") {
        return Some(PathBuf::from(path));
    }
    let home = std::env::var_os("CODEX_HOME")
        .map(PathBuf::from)
        .or_else(|| {
            std::env::var_os("USERPROFILE")
                .or_else(|| std::env::var_os("HOME"))
                .map(PathBuf::from)
        })?;
    Some(home.join(LOCK_FILE_NAME))
}

fn load_lock_config(
    path: Option<&Path>,
    read: impl Fn(&Path) -> Option<String>,
) -> LockConfig {
    let Some(path) = path else {
        return LockConfig::default();
    };
    let Some(text) = read(path) else {
        tracing::warn!(
            path = %path.display(),
            "lock config unreadable; using locked defaults"
        );
        return LockConfig::default();
    };
    parse_lock_config(&text)
}

/// Parses the `proxy` and `timezone` keys. Unknown keys and malformed lines are
/// ignored; values must be quoted strings.
pub(crate) fn parse_lock_config(text: &str) -> LockConfig {
    let mut config = LockConfig::default();
    for line in text.lines() {
        let line = line.trim();
        if line.is_empty() || line.starts_with('#') {
            continue;
        }
        let Some((key, value)) = line.split_once('=') else {
            continue;
        };
        let Some(value) = parse_toml_string(value.trim()) else {
            continue;
        };
        match key.trim() {
            "proxy" => config.proxy_url = Some(value),
            "timezone" => config.timezone = Some(value),
            _ => {}
        }
    }
    config
}

/// Extracts a leading single- or double-quoted string; trailing content
/// (comments) after the closing quote is ignored.
fn parse_toml_string(raw: &str) -> Option<String> {
    let quote = raw.chars().next()?;
    if quote != '"' && quote != '\'' {
        return None;
    }
    let rest = &raw[quote.len_utf8()..];
    let end = rest.find(quote)?;
    Some(rest[..end].to_string())
}

#[cfg(test)]
#[path = "lock_config_tests.rs"]
mod tests;
