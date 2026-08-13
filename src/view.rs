//! The document view — where the typography lives.

use gpui::{
    App, Context, IntoElement, ParentElement, Render, StyleRefinement, Styled, Window, div, px,
    rems,
};
use gpui_component::{
    ActiveTheme,
    text::{TextView, TextViewStyle},
    v_flex,
};

use orri_core::Doc;

/// Reading measure: ~68 characters at 16px.
///
/// The single highest-impact typographic choice in the whole app, and the one
/// thing every browser-based preview gets wrong by rendering text full-width.
const MEASURE: f32 = 680.;

/// Side gutters, so the measure never touches the window edge.
const GUTTER: f32 = 32.;

/// Clears the traffic lights, which float over content in a borderless window.
const TOP_INSET: f32 = 30.;

const BODY_SIZE: f32 = 16.;

pub struct DocView {
    doc: Doc,
}

impl DocView {
    pub fn new(doc: Doc) -> Self {
        Self { doc }
    }

    pub fn set_text(&mut self, raw: &str) {
        self.doc = Doc::parse(raw);
    }
}

/// A 1.2 modular scale off the 16px body, rather than the `base + 6` bump that
/// makes h1/h2/h3 read as three sizes of the same thing.
fn heading_size(level: u8) -> f32 {
    match level {
        1 => 27.6,
        2 => 23.,
        3 => 19.2,
        // h4 matches body size and leans on weight alone.
        4 => BODY_SIZE,
        _ => 14.,
    }
}

impl Render for DocView {
    fn render(&mut self, window: &mut Window, cx: &mut Context<Self>) -> impl IntoElement {
        let theme = cx.theme();
        let is_dark = theme.mode.is_dark();
        let background = theme.background;
        let foreground = theme.foreground;

        let mut style = TextViewStyle::default()
            .paragraph_gap(rems(0.9))
            .heading_font_size(|level, _base| px(heading_size(level)))
            // Borderless, lightly tinted code — no box inside a box.
            .code_block(
                StyleRefinement::default()
                    .bg(foreground.opacity(0.04))
                    .rounded_md(),
            );
        style.heading_base_font_size = px(BODY_SIZE);
        style.highlight_theme = theme.highlight_theme.clone();
        style.is_dark = is_dark;

        v_flex()
            .size_full()
            .bg(background)
            .text_color(foreground)
            .text_size(px(BODY_SIZE))
            // The native titlebar stays present but transparent, so this inset
            // is only about keeping text clear of the traffic lights.
            .pt(px(TOP_INSET))
            .child(
                div()
                    .flex_1()
                    // Without min-height:0 a flex child refuses to shrink, and
                    // the scroll container never gets a bounded height.
                    .min_h_0()
                    .w_full()
                    .child(
                        v_flex()
                            .h_full()
                            .w_full()
                            .max_w(px(MEASURE))
                            .mx_auto()
                            .px(px(GUTTER))
                            .children(self.frontmatter(cx))
                            .child(
                                TextView::markdown("doc", self.doc.body.clone(), window, cx)
                                    .selectable(true)
                                    .scrollable(true)
                                    .style(style),
                            ),
                    ),
            )
    }
}

impl DocView {
    /// A dim key/value header, pinned above the scroll area.
    ///
    /// Pinning is deliberate: on a wiki page the frontmatter *is* the page's
    /// identity, and it stays useful while you read the body.
    fn frontmatter(&self, cx: &App) -> Option<impl IntoElement + use<>> {
        if self.doc.meta.is_empty() {
            return None;
        }

        let theme = cx.theme();
        let key_color = theme.muted_foreground;
        let value_color = theme.foreground.opacity(0.85);
        let border = theme.border.opacity(0.6);

        Some(
            v_flex()
                .flex_none()
                .gap_1()
                .pb_3()
                .mb_5()
                .border_b_1()
                .border_color(border)
                .text_xs()
                .children(self.doc.meta.iter().map(move |(key, value)| {
                    gpui_component::h_flex()
                        .gap_3()
                        .items_start()
                        .child(
                            div()
                                .flex_none()
                                .w(px(64.))
                                .text_color(key_color)
                                .child(key.clone()),
                        )
                        .child(div().flex_1().text_color(value_color).child(value.clone()))
                })),
        )
    }
}
