---
name: Closeup
description: Your Android phone as your Mac's webcam, told in heavy type over the icon's glow on a night ground.
colors:
  night-ground: "#0D0C12"
  night-ink: "#F6F1EC"
  night-body: "#CBC5D1"
  night-muted: "#958FA1"
  night-rule: "rgb(246 241 236 / 0.12)"
  night-raised: "#1B1922"
  night-scroll: "#34303D"
  icon-orange: "#FF8757"
  icon-amber: "#FFC56E"
  icon-pink: "#EE4D6A"
  icon-indigo: "#3B40BC"
  docs-accent: "#C23A1C"
  on-docs-accent: "#FFFFFF"
  docs-paper: "#F5F5F2"
  docs-ink: "#161616"
  docs-ink-night: "#F3EEE9"
  docs-body: "#2E2E2C"
  docs-body-night: "#D6D1DA"
  docs-muted: "#64645F"
  docs-muted-night: "#A29DAB"
  docs-border: "#E0E0DB"
  docs-border-night: "#26232F"
  docs-surface: "#EBEBE7"
  docs-code: "#EDEDEA"
  docs-code-night: "#08070C"
  docs-scroll: "#CFCFCA"
typography:
  hero-statement:
    fontFamily: "Timeless Sans, sans-serif"
    fontSize: "clamp(3.25rem, 7.4vw, 7.25rem)"
    fontWeight: 800
    lineHeight: 0.92
    letterSpacing: "-0.045em"
  big-statement:
    fontFamily: "Timeless Sans, sans-serif"
    fontSize: "clamp(3rem, 9vw, 9rem)"
    fontWeight: 800
    lineHeight: 0.9
    letterSpacing: "-0.05em"
  section-statement:
    fontFamily: "Timeless Sans, sans-serif"
    fontSize: "clamp(2.5rem, 5.4vw, 5rem)"
    fontWeight: 800
    lineHeight: 0.95
    letterSpacing: "-0.045em"
  step-numeral:
    fontFamily: "Timeless Sans, sans-serif"
    fontSize: "clamp(3.5rem, 5vw, 4.75rem)"
    fontWeight: 800
    lineHeight: 1
    letterSpacing: "-0.05em"
    fontFeature: "\"tnum\""
  wordmark:
    fontFamily: "Timeless Sans, sans-serif"
    fontSize: "clamp(1.75rem, 2.4vw, 2.25rem)"
    fontWeight: 800
    letterSpacing: "-0.035em"
  docs-display:
    fontFamily: "Timeless Sans, sans-serif"
    fontSize: "2.75rem"
    fontWeight: 700
    letterSpacing: "-0.02em"
  docs-headline:
    fontFamily: "Timeless Sans, sans-serif"
    fontSize: "1.625rem"
    fontWeight: 700
    letterSpacing: "-0.02em"
  intro:
    fontFamily: "Timeless Sans, sans-serif"
    fontSize: "clamp(1.125rem, 1rem + 0.35vw, 1.3125rem)"
    fontWeight: 400
    lineHeight: 1.55
  step-title:
    fontFamily: "Timeless Sans, sans-serif"
    fontSize: "1.125rem"
    fontWeight: 700
    letterSpacing: "-0.01em"
  body:
    fontFamily: "Timeless Sans, sans-serif"
    fontSize: "1rem"
    fontWeight: 400
    lineHeight: 1.7
  step:
    fontFamily: "Timeless Sans, sans-serif"
    fontSize: "1rem"
    fontWeight: 400
    lineHeight: 1.55
  fine:
    fontFamily: "Timeless Sans, sans-serif"
    fontSize: "0.9375rem"
    fontWeight: 400
  mono:
    fontFamily: "Geist Mono, monospace"
  ascii-glyph:
    fontFamily: "SF Mono, ui-monospace, Menlo, monospace"
    fontSize: "16px"
    fontWeight: 300
rounded:
  pill: "999px"
  control: "6px"
  md: "0.5rem"
spacing:
  xs: "0.75rem"
  sm: "1rem"
  md: "1.5rem"
  lg: "1.75rem"
  xl: "2.25rem"
  2xl: "2.5rem"
components:
  button-glow:
    backgroundColor: "{colors.icon-orange}"
    textColor: "{colors.night-ground}"
    typography: "{typography.step-title}"
    rounded: "{rounded.pill}"
    padding: "0 1.875rem"
    height: "3.375rem"
  button-glow-hover:
    backgroundColor: "{colors.icon-amber}"
    textColor: "{colors.night-ground}"
  link-night:
    textColor: "{colors.night-ink}"
  link-night-hover:
    textColor: "{colors.icon-amber}"
  link-docs:
    textColor: "{colors.docs-body}"
    typography: "{typography.body}"
  link-docs-hover:
    textColor: "{colors.docs-accent}"
  link-docs-night-hover:
    textColor: "{colors.icon-orange}"
---

# Design System: Closeup

## Overview

**Creative North Star: "The Icon After Dark"**

The home page is Closeup's app icon, turned into a place. It's always night there: a near-black ground with the icon's own gradient (lens indigo into pink, orange and amber) drawn as a field of drifting ASCII glyphs that glow like a horizon behind the opening screen and rise again under the closing one. Over that glow the site talks in big, heavy statements, set tight, and shows the real app windows sitting in soft pools of the same colors. The logo is on the page twice, as a lockup above the first statement and large over the close.

There's one typeface, Timeless Sans, from regular body text up to the black weight for the statements, so the page gets its drama from weight and scale rather than from a second face. The docs are the daytime part of the same building: Blume's three columns on a warm white paper (or the same night ground in dark mode), with a deep orange accent by day and the icon's orange by night. Harsha pinned these choices on 2026-10-29: no serif fonts, Timeless Sans with large heavyweight statements, the React Bits GradientASCII background, and Closeup's logo on the page.

Density is low: one idea per row, lots of dark space between them, and every word readable from the first frame even while the glyphs are still settling in.

**Key Characteristics:**
- Always-night home page on a near-black ground, the same in light and dark mode.
- The icon's gradient as a living ASCII glow, at the hero and at the close only.
- Timeless Sans for every word, statements at 800 with tight tracking.
- An orange pill button that catches the glow; amber on hover.
- Real app windows in soft pools of the icon's colors, never in device frames.
- The Closeup logo on the page, not just in the nav.

## Colors

The icon's four colors on a night ground for the home page, and a quiet paper and ink set with one orange accent for the docs.

### Primary
- **Icon Orange**: the color that acts on the home page. It fills the Download button, underlines links at 65%, colors the step numerals and the last line of the big statement ("No cloud."), tints selection at 30% and the glow under the button and logo. In dark mode docs it's also the accent.
- **Docs Accent**: a deeper burnt orange that carries the same role on the light docs page, where Icon Orange would be too pale on paper: link hovers, 55% link underlines, focus rings, the caret and form accents, with white text on it.

### Secondary
- **Icon Amber**: the hover state. The button turns amber with an amber glow, links turn amber, and focus rings on the home page are amber.

### Tertiary
- **Icon Pink** and **Icon Indigo**: the other two stops of the icon's gradient. They only appear as light: in the ASCII glow, and as the soft pools behind screenshots (pink is the default pool, indigo sits behind Setup, orange behind Check Audio Sync).

### Neutral
- **Night Ground**: the home page background, and the docs background in dark mode.
- **Night Ink**: warm off-white for statements, headings, the wordmark and step titles.
- **Night Body**: the intro and feature paragraphs.
- **Night Muted**: fine print and step descriptions.
- **Night Rule**: the 1px rule on top of each step.
- **Night Raised** and **Night Scroll**: Blume's muted surfaces and the scrollbar thumb at night.
- **Docs Paper**, **Docs Ink**, **Docs Body**, **Docs Muted**, **Docs Border**, **Docs Surface**, **Docs Code**, **Docs Scroll**: the light docs, with night values where dark mode changes them.

### Named Rules
**The Icon Palette Rule.** Every color on the home page comes from the icon or from the night. Indigo, pink, orange and amber, plus the ground and its inks. Nothing else.

**The One Hand Rule.** Orange is the only color you click (amber is its hover). Indigo and pink are light, never buttons or links.

**The Always Night Rule.** The home page ignores the theme switch; it's night in both modes. The docs follow the switch.

## Typography

**Display Font:** Timeless Sans (with sans-serif fallback), self-hosted, weights 400, 500, 600, 700 and 800
**Body Font:** Timeless Sans
**Label/Mono Font:** Geist Mono for code in the docs; the ASCII glow draws its glyphs in SF Mono at 300

**Character:** One grotesque, pushed to its black weight and tracked tight for statements that read like a poster, then relaxed to regular for plain, friendly paragraphs.

### Hierarchy
- **Hero Statement** (800, `clamp(3.25rem, 7.4vw, 7.25rem)`, line-height 0.92, -0.045em): the first screen's h1, balanced, up to 10.5em wide.
- **Big Statement** (800, `clamp(3rem, 9vw, 9rem)`, line-height 0.9, -0.05em): the stacked "No app on the phone. No account. No cloud." lines, one per row.
- **Section Statement** (800, `clamp(2.5rem, 5.4vw, 5rem)`, line-height 0.95, -0.045em): feature headings and "Your first call." The closing line goes up to `clamp(2.75rem, 7vw, 6.5rem)`.
- **Step Numeral** (800, `clamp(3.5rem, 5vw, 4.75rem)`, -0.05em, tabular figures, Icon Orange): the step numbers.
- **Wordmark** (800, `clamp(1.75rem, 2.4vw, 2.25rem)`, -0.035em): "Closeup" beside the logo in the hero lockup.
- **Docs Display** (700, 2.75rem) and **Docs Headline** (700, 1.625rem), both -0.02em: docs titles and section headings.
- **Intro** (400, `clamp(1.125rem, 1rem + 0.35vw, 1.3125rem)`, line-height 1.55): the hero paragraph (up to 32rem) and the aside under the big statement. Feature paragraphs run a step smaller, `clamp(1.0625rem, 1rem + 0.25vw, 1.25rem)`, up to 28rem.
- **Step Title** (700, 1.125rem, -0.01em): step titles. The button uses the same size and weight.
- **Body** (400, 1rem, line-height 1.7): docs prose, with strong text at 600. Tables are 0.9375rem with tabular figures.
- **Step** (400, 1rem, line-height 1.55) and **Fine** (400, 0.9375rem): step descriptions and the requirements line.

### Named Rules
**The No Serif Rule.** Timeless Sans for every word, Geist Mono only in code, a system mono only inside the ASCII glow. No serif, no second display face.

**The Heavy Statement Rule.** Statements are 800 with tracking between -0.045em and -0.05em and line-height under 1. Everything you read to learn something is 400. Little sits in between.

## Layout

The home page is a stack of full-width bands, each with its content in an 82rem column padded `clamp(1.25rem, 4vw, 3rem)` at the sides.

The hero fills the viewport less 4rem. The ASCII glow covers the whole band behind a scrim (dark from the left, fading out by 75%, plus a fade to the ground at the bottom) so the words always read. On top sits a two-column grid: the logo lockup, statement, intro, buttons and fine print on the left, and Live Controls on the right at its true width, between 15rem and 20rem depending on viewport height (`(100svh - 14rem) * 0.4194`).

Then the big statement band, then three feature rows: copy and a real window side by side (copy at 1fr, window at 1.15fr), the middle row flipped. Then four steps in a row (two at 1080px and under, one at 520px and under). The close is centered: the logo at 5.5rem to 7rem, the closing statement, buttons and fine print, with the glow rising from the bottom edge.

At 820px and under the hero and features stack, the hero scrim turns vertical, and Live Controls centers at `min(17.5rem, 72vw)`.

Spacing steps that repeat: 0.75rem (button row gap), 1rem (logo to wordmark, numeral to title), 1.5rem (heading to paragraph), 1.75rem (button to link), 2.25rem (intro to buttons), 2.5rem (row gap between steps, stacked feature gap). Bands are spaced with `svh` clamps so they breathe with the viewport.

Docs pages use Blume's three-column layout untouched. Screenshots in docs center at their natural size, never taller than 40rem.

## Elevation & Depth

Depth comes from light behind things and shadow under them. The ASCII glow is the deepest layer, then a scrim, then content. Screenshots on the home page sit in a radial pool of one icon color (50% at the center, 16% halfway, then nothing) and cast a long black shadow with a hairline white rim so the dark window edge reads on the dark ground. The logo and the button glow orange, as if lit by the field. In the docs, screenshots cast a soft downward shadow on paper, and the night version adds the same white rim.

### Shadow Vocabulary
- **Night Window** (`drop-shadow(0 34px 44px rgb(0 0 0 / 0.65)) drop-shadow(0 0 1px rgb(255 255 255 / 0.25))`): every screenshot on the home page.
- **Button Glow** (`box-shadow: 0 12px 32px -10px rgb(255 135 87 / 0.7)`; hover `0 14px 38px -10px rgb(255 197 110 / 0.75)`): the orange pill.
- **Logo Glow** (`drop-shadow(0 10px 24px rgb(255 135 87 / 0.35))` in the lockup, `drop-shadow(0 16px 40px rgb(255 135 87 / 0.45))` at the close): the icon.
- **Docs Figure** (`drop-shadow(0 14px 24px rgb(22 22 20 / 0.18)) drop-shadow(0 1px 2px rgb(22 22 20 / 0.16))`; night `0 14px 28px` black at 60% plus the white rim at 22%): docs screenshots.

### Named Rules
**The Glow Stays Put Rule.** The ASCII glow lives at the hero (horizon shape) and the close (rise shape) and nowhere else. The middle of the page is plain night with pools of light.

**The Readable First Rule.** Words always sit on a scrim over the glow, and the page reads before the glyphs finish arriving.

## Shapes

The one button is a full pill (999px). Docs controls and focus rings use 6px; Blume's cards, code blocks and tables use 0.5rem. Screenshots are macOS windows with transparent corners, so their own corners are the shape; they're never clipped or framed. The pools of light are soft ellipses with no edge. The only lines on the home page are the 1px rules on top of each step.

## Components

### Buttons
Bright, round and warm, the one thing on the page that's lit from inside.
- **Shape:** full pill (999px).
- **Primary:** Icon Orange fill, Night Ground text, 1.0625rem at 700 with -0.01em tracking, 3.375rem tall, 1.875rem side padding, with the Button Glow.
- **Hover / Focus:** turns Icon Amber with an amber glow over 160ms ease-out. Focus is a 2px amber outline 4px out. Reduced motion drops the transitions.
- **Secondary:** no ghost or outlined buttons. The second action is a link.

### Links
On the home page: Night Ink, 1.0625rem at 500, with a 1.5px orange underline at 65%, 0.25em offset; amber on hover over 150ms. In the docs: Docs Body text with a 1px accent underline at 55%, 0.22em offset; accent on hover.

### Logo Lockup
The app icon at 3.5rem to 4.5rem with the Logo Glow, 1rem from the wordmark. It opens the hero above the statement. The close repeats the icon alone, larger.

### Gradient ASCII Field
The React Bits GradientASCII component (WebGL2), vendored into `site/islands` and credited on the docs Credits page. It draws the icon's gradient in the stops indigo, pink, orange, amber as a field of glyphs (` =+xX0S8#@`) on a 16px grid, with glow 0.35, flow 0.45 and speed 0.6. The pointer scrambles nearby glyphs (radius 0.08) and a click sends a ripple. The hero field plays a 2.4s intro and loads at once; the close field skips the intro and loads when it scrolls into view. Under reduced motion it holds a still frame with no flicker, intro or pointer effects. It's decorative and hidden from assistive tech.

### Feature Row
A Section Statement and one short paragraph beside a real app window in its pool of light. Rows alternate sides.

### Steps
Four steps after a 1px Night Rule each: a big orange numeral, the title in Step Title, then a sentence in Night Muted.

### Navigation
Blume's header with the icon and "Closeup", Docs and GitHub, themed by tokens. On the home page it sits on the night ground.

## Do's and Don'ts

### Do:
- **Do** keep the home page on Night Ground in both light and dark mode.
- **Do** use only the icon's four colors on the home page, with orange (amber on hover) as the only one you click.
- **Do** set statements in Timeless Sans 800 with tight tracking, and paragraphs at 400.
- **Do** show the Closeup logo on the page, in the hero lockup and at the close.
- **Do** keep the GradientASCII glow to the hero and the close, behind a scrim, and credit React Bits.
- **Do** put real app windows in a soft pool of one icon color with the Night Window shadow.
- **Do** theme docs pages through tokens only and leave Blume's layout alone.

### Don't:
- **Don't** use serif fonts, or any face but Timeless Sans outside code.
- **Don't** use indigo or pink for buttons, links or text; they're light.
- **Don't** add badges, chips, icon tiles or gradients beyond the ASCII glow, the pools and the scrims.
- **Don't** put a screenshot in a device frame or a box; its own corners are its shape.
- **Don't** let words sit directly on moving glyphs without a scrim.
- **Don't** bring the night ground or the glow into the light docs.
