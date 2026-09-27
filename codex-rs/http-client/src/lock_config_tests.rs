//! Tests for the fork lock configuration parser.

use super::*;

#[test]
fn parses_proxy_and_timezone() {
    let config = parse_lock_config(
        "# comment\nproxy = \"http://127.0.0.1:10809\"\ntimezone = 'Asia/Shanghai'\n",
    );
    assert_eq!(
        config,
        LockConfig {
            proxy_url: Some("http://127.0.0.1:10809".to_string()),
            timezone: Some("Asia/Shanghai".to_string()),
        }
    );
}

#[test]
fn empty_file_yields_defaults() {
    let config = parse_lock_config("");
    assert_eq!(config, LockConfig::default());
    assert_eq!(config.proxy_url(), DEFAULT_LOCK_PROXY_URL);
    assert_eq!(config.timezone(), DEFAULT_LOCK_TIMEZONE);
}

#[test]
fn empty_values_fall_back_to_defaults() {
    let config = parse_lock_config("proxy = \"\"\ntimezone = ''\n");
    assert_eq!(config.proxy_url(), DEFAULT_LOCK_PROXY_URL);
    assert_eq!(config.timezone(), DEFAULT_LOCK_TIMEZONE);
}

#[test]
fn ignores_unknown_keys_malformed_lines_and_trailing_comments() {
    let config = parse_lock_config(
        "unknown = \"value\"\nnot-a-pair\nproxy = \"socks5://127.0.0.1:10808\" # trailing\n",
    );
    assert_eq!(config.proxy_url(), "socks5://127.0.0.1:10808");
    assert_eq!(config.timezone(), DEFAULT_LOCK_TIMEZONE);
}

#[test]
fn missing_keys_keep_defaults() {
    let config = parse_lock_config("proxy = \"http://proxy.example:8080\"\n");
    assert_eq!(config.proxy_url(), "http://proxy.example:8080");
    assert_eq!(config.timezone(), DEFAULT_LOCK_TIMEZONE);
}
