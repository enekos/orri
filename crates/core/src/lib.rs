//! Frontend-agnostic core for orri.
//!
//! Everything here is shared between frontends: the macOS GPUI app, and the
//! terminal reader that runs under Termux on an e-ink tablet. Nothing in this
//! crate knows about rendering, GPUs, or terminals — it parses documents and
//! carries editor frames.

pub mod doc;
pub mod sync;

pub use doc::{Doc, WIKI_SCHEME};
pub use sync::{Msg, default_socket_path, listen};
