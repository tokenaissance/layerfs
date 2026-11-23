//! What one host operation answers: a value, or a refusal with a stable
//! code. Moved from layerfs-node's job.rs (#533 step 2).
use layerfs_bridge::control::{SdkRefusal, SdkValue};

/// What one operation answers.
pub type Outcome = Result<SdkValue, SdkRefusal>;

/// A refusal with a stable code.
pub fn refused(code: &str, message: impl Into<String>) -> SdkRefusal {
    SdkRefusal {
        code: code.to_owned(),
        message: message.into(),
        detail: SdkValue::Null,
    }
}

/// A failure that has no SDK code of its own.
pub fn failed(error: impl std::fmt::Debug) -> SdkRefusal {
    refused("Failed", format!("{error:?}"))
}

/// A name as one shell word. Store and machine names are validated names,
/// so the bare text is already one word; this exists for display sites that
/// used the helper before the names were checked at the call boundary.
pub fn shell_word(value: &str) -> String {
    value.to_owned()
}

/// Which shape of an entity a call answers (#536 §9.7): a get's whole
/// record, or one item of a list.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum View {
    /// What the entity's get answers.
    Full,
    /// One item of the entity's list.
    List,
}
