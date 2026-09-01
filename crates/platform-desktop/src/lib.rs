mod desktop;
mod walk_prune;
mod application_inventory;
mod browser_privacy;

pub use application_inventory::{ApplicationAnalyzer, ApplicationCandidate, ApplicationInventory};
pub use browser_privacy::{BrowserPrivacyAnalyzer, BrowserPrivacyInventory};
pub use desktop::DesktopPlatform;
