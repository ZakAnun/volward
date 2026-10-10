//! Pack list prices: USD cents are authoritative for Paddle/App; CNY (fen) is implied at FX for planning.

/// Yuan per US dollar — used to derive `price_cny` from list USD when needed.
pub const CNY_YUAN_PER_USD: f64 = 7.2;

pub const TRIAL_USD_CENTS: i64 = 149;
pub const STANDARD_USD_CENTS: i64 = 299;
pub const PLUS_USD_CENTS: i64 = 649;
pub const MAX_USD_CENTS: i64 = 1299;

/// Locked checkout cents for a pack id. Prefer DB `price_usd_cents` when set.
pub fn locked_list_usd_cents(pack_id: &str) -> Option<i64> {
    match pack_id {
        "trial" => Some(TRIAL_USD_CENTS),
        "standard" => Some(STANDARD_USD_CENTS),
        "plus" => Some(PLUS_USD_CENTS),
        "max" => Some(MAX_USD_CENTS),
        _ => None,
    }
}

pub fn pack_list_usd_cents(pack_id: &str, stored: Option<i64>) -> i64 {
    match stored {
        Some(v) if v > 0 => v,
        _ => locked_list_usd_cents(pack_id).unwrap_or(0),
    }
}

/// Implied planning CNY (fen) from a USD list price in cents.
pub fn usd_cents_to_cny_fen(usd_cents: i64) -> i64 {
    if usd_cents <= 0 {
        return 0;
    }
    let yuan = (usd_cents as f64) / 100.0 * CNY_YUAN_PER_USD;
    (yuan * 100.0).round() as i64
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn list_usd_cents_imply_cny_fen_at_fx() {
        assert_eq!(usd_cents_to_cny_fen(TRIAL_USD_CENTS), 1073);
        assert_eq!(usd_cents_to_cny_fen(STANDARD_USD_CENTS), 2153);
        assert_eq!(usd_cents_to_cny_fen(PLUS_USD_CENTS), 4673);
        assert_eq!(usd_cents_to_cny_fen(MAX_USD_CENTS), 9353);
    }

    #[test]
    fn pack_list_prefers_stored_then_locked_id() {
        assert_eq!(pack_list_usd_cents("trial", Some(149)), 149);
        assert_eq!(pack_list_usd_cents("trial", None), TRIAL_USD_CENTS);
        assert_eq!(pack_list_usd_cents("trial", Some(0)), TRIAL_USD_CENTS);
        assert_eq!(pack_list_usd_cents("unknown", None), 0);
    }
}
