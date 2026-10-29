---
name: Closeup
description: Your Android phone as your Mac's webcam, shown like a single work on a white gallery wall.
colors:
  lens-indigo: "#3F3FB8"
  lens-indigo-night: "#9494F7"
  on-indigo: "#FFFFFF"
  on-indigo-night: "#111111"
  gallery-wall: "#F5F5F2"
  gallery-wall-night: "#141414"
  ink: "#161616"
  ink-night: "#EDEDEA"
  body-ink: "#2E2E2C"
  body-ink-night: "#D4D4CF"
  label-gray: "#64645F"
  label-gray-night: "#9B9B95"
  hairline: "#E0E0DB"
  hairline-night: "#2B2B29"
  muted-wall: "#EBEBE7"
  muted-wall-night: "#1F1F1E"
  code-wall: "#EDEDEA"
  code-wall-night: "#0E0E0E"
  spotlight: "#FFFFFF"
  spotlight-night: "#222221"
  scroll-thumb: "#CFCFCA"
  scroll-thumb-night: "#3A3A38"
typography:
  display:
    fontFamily: "Switzer, sans-serif"
    fontSize: "2.75rem"
    fontWeight: 600
    letterSpacing: "-0.02em"
  headline:
    fontFamily: "Switzer, sans-serif"
    fontSize: "1.625rem"
    fontWeight: 600
    letterSpacing: "-0.02em"
  wall-label:
    fontFamily: "Switzer, sans-serif"
    fontSize: "clamp(1.0625rem, 0.95rem + 0.3vw, 1.25rem)"
    fontWeight: 400
    lineHeight: 1.5
    letterSpacing: "0"
  body:
    fontFamily: "Switzer, sans-serif"
    fontSize: "1rem"
    fontWeight: 400
    lineHeight: 1.7
  label:
    fontFamily: "Switzer, sans-serif"
    fontSize: "1rem"
    fontWeight: 400
    lineHeight: 1.55
    fontFeature: "\"tnum\""
  table:
    fontFamily: "Switzer, sans-serif"
    fontSize: "0.9375rem"
    fontFeature: "\"tnum\""
  mono:
    fontFamily: "Geist Mono, monospace"
rounded:
  control: "6px"
  md: "0.5rem"
spacing:
  xs: "0.75rem"
  sm: "1rem"
  md: "1.5rem"
  lg: "2rem"
components:
  button-primary:
    backgroundColor: "{colors.lens-indigo}"
    textColor: "{colors.on-indigo}"
    rounded: "{rounded.control}"
    padding: "0 1.375rem"
    height: "2.875rem"
  button-primary-night:
    backgroundColor: "{colors.lens-indigo-night}"
    textColor: "{colors.on-indigo-night}"
    rounded: "{rounded.control}"
    padding: "0 1.375rem"
    height: "2.875rem"
  link-quiet:
    textColor: "{colors.ink}"
    typography: "{typography.body}"
  link-quiet-hover:
    textColor: "{colors.lens-indigo}"
  wall-label:
    textColor: "{colors.body-ink}"
    typography: "{typography.wall-label}"
    width: "22rem"
  step-label:
    textColor: "{colors.label-gray}"
    typography: "{typography.label}"
    padding: "1rem 0 0"
---

# Design System: Closeup

## Overview

**Creative North Star: "The Single Work on a Gallery Wall"**

Closeup's site is a quiet room. The real app, its Live Controls panel at its true size, hangs on a matte white wall under one light, and a small wall label beside it says what it is, what it needs and how to get it. Nothing else competes. The visitor reads the label the way they'd read one in a gallery: name in a heavier weight, then a few plain lines, then the one thing to do.

Density is low and type is calm. The landing page gets almost all of its hierarchy from weight and ink, not size, and the docs pages keep that voice through tokens alone: same wall, same ink, same single indigo, same light from above. Dark mode isn't a different look. It's the same gallery after hours, with a dimmer wall and a dimmer spotlight.

The world rejects the dark gradient SaaS hero, the centered headline over a device mockup, and the old warm gray type poster it replaced.

**Key Characteristics:**
- Matte off-white wall and near-black ink, with a gray for secondary lines.
- One indigo, taken from the icon's lens, only on things you can click.
- One light source from above: a soft spotlight on the wall, every shadow cast downward.
- Switzer for all text, Geist Mono for code.
- Real screenshots at near their real size, never in device frames.

## Colors

A near-neutral gallery palette (wall, ink, label gray) with a single cool indigo accent, in a light and a dark set.

### Primary
- **Lens Indigo** (light and night values in the frontmatter): the color of the lens in the app icon. It fills the Download for Mac button, tints link underlines at 55%, turns links fully indigo on hover, and drives the focus ring, text caret, form accent and the 16% (light) or 24% (night) selection tint. Text on it is white in light mode and near-black in dark mode.

### Neutral
- **Gallery Wall**: the page background. Matte off-white by day, deep charcoal after hours.
- **Ink**: headings, strong text, the wall label's name and the step titles.
- **Body Ink**: running text in docs and the wall label's sentences. A touch softer than Ink so headings stand out without growing.
- **Label Gray**: secondary lines on the wall label (the date line and the requirements), the step descriptions and their numbers.
- **Hairline**: the 1px rule above each step and Blume's borders.
- **Muted Wall** and **Code Wall**: Blume's muted surfaces and code block background, one step off the wall.
- **Spotlight**: the center of the light pool on the wall. Pure white by day; by night a gray just above the wall.
- **Scroll Thumb**: the scrollbar thumb, on a transparent track.

### Named Rules
**The Lens Rule.** Indigo goes only on what acts: the Download button, links, focus and text selection. If you can't click it, it isn't indigo.

**The After Hours Rule.** Dark mode keeps every role and only dims the room. Never add a color in dark mode that light mode doesn't have.

## Typography

**Display Font:** Switzer (with sans-serif fallback), weights 400, 500 and 600, from Fontshare
**Body Font:** Switzer (with sans-serif fallback)
**Label/Mono Font:** Geist Mono, for code in the docs only

**Character:** One neutral grotesque does everything, so the site reads like a well-set museum label rather than an ad. Headings tighten slightly (-0.02em); the wall label doesn't.

### Hierarchy
- **Display** (600, 2.75rem): the title of a docs page.
- **Headline** (600, 1.625rem): docs section headings.
- **Wall Label** (400 with 600 for the name, fluid 1.0625rem to 1.25rem, line-height 1.5): the landing page's label. One size for every line; the name is 600 in Ink, the sentences 400 in Body Ink, the date and requirements 400 in Label Gray.
- **Body** (400, 1rem, line-height 1.7): docs prose in Body Ink, with strong text in Ink at 600.
- **Label** (400, 1rem, line-height 1.55, tabular figures): the four numbered steps. Title in Ink at 600, description and number in Label Gray.
- **Table** (0.9375rem, tabular figures): docs tables.

### Named Rules
**The Weight Not Size Rule.** On the landing page, hierarchy comes from weight and ink. The page's h1 is the same size as the sentence under it. Don't scale up a headline to make a point.

**The One Face Rule.** Switzer for every word you read, Geist Mono only inside code.

## Layout

The landing page is one full-width wall under the nav, padded `clamp(3rem, 8svh, 6rem)` on top, 1.5rem at the sides and `clamp(5rem, 12svh, 9rem)` at the bottom. The first view is a two-column grid, centered as a pair: the panel on the left at its own width, the wall label on the right at up to 22rem, vertically centered on each other with a gap of `clamp(3.5rem, 8vw, 8rem)`. The hero fills the viewport less 12rem, so the steps peek in below.

The panel image is at most 20rem (320px, its true size) and shrinks with viewport height (`(100svh - 13rem) * 0.4194`, the panel's aspect) down to 15rem, so the whole panel always fits on screen.

Below, "Your first call" sits in a 68rem column: four equal steps in a row, two at 900px and under, one at 520px and under. At 760px and under the hero stacks, the panel centers at `min(17.5rem, 72vw)`, and the label sits below it.

Spacing steps that repeat: 0.75rem (button row gap, step number to title), 1rem (step padding above), 1.5rem (side padding, button to link, heading to steps), 2rem (label to buttons, row gap between steps). Lines inside the wall label are grouped with a 1.25em gap, not spaced evenly.

Docs pages use Blume's three-column layout untouched. Screenshots in docs center in the column at their natural size, never taller than 40rem.

## Elevation & Depth

Depth comes from one light above the wall. A radial spotlight, the only gradient on the site, sits behind the hung panel, its top edge above the panel and its pool fading to transparent. Every hung object (the landing panel, docs screenshots) casts a soft shadow straight down: a long blur plus a tight contact shadow. In dark mode the contact shadow becomes a 1px white rim at 22% so the dark window edge still separates from the dark wall. Flat UI (buttons, step labels, text) casts nothing.

### Shadow Vocabulary
- **Hung Work** (`drop-shadow(0 32px 36px var(--closeup-shadow)) drop-shadow(0 2px 3px var(--closeup-shadow-near))`): the landing page's panel. Dark: `0 32px 40px` plus the white rim.
- **Hung Figure** (`drop-shadow(0 14px 24px var(--closeup-shadow)) drop-shadow(0 1px 2px var(--closeup-shadow-near))`): screenshots in docs. Dark: `0 14px 28px` plus the white rim.
- Shadow color is ink at 18% (far) and 16% (near) by day, black at 60% and 50% by night.

### Named Rules
**The One Light Rule.** There's one light and it's above. Every shadow has zero x-offset and a positive y-offset; nothing glows, nothing lifts toward the viewer on hover.

**The Hung Object Rule.** Only things hung on the wall (real app windows and panels) get a shadow, and it's a drop-shadow filter that follows the window's own transparent corners, never a box-shadow on a frame.

## Shapes

Corners are small and practical. Blume's surfaces (cards, code blocks, tables) use 0.5rem. The Download button and every focus ring use 6px. Screenshots aren't clipped or framed: they're macOS windows exported with transparent corners, so their own rounded corners are the shape. Grouping is done with a single 1px hairline rule on top, not boxes.

## Components

### Buttons
Plain and confident, the only filled thing on the page.
- **Shape:** gently rounded (6px).
- **Primary:** Lens Indigo fill, white text (near-black at night), 1rem at 500, 2.875rem tall, 1.375rem side padding.
- **Hover / Focus:** hover mixes 16% of Ink into the indigo over 160ms ease-out. Focus is a 2px indigo outline 3px out. Reduced motion drops the transition.
- **Secondary:** there's no outlined or ghost button. The second action is a quiet link.

### Quiet Link
The secondary action and every docs link: Ink (Body Ink in prose) text with a 1px underline in indigo at 55%, offset about 0.22em to 0.25em. Hover turns the text indigo over 150ms ease-out.

### Wall Label
The landing page's call to action. Up to 22rem wide, one type size, lines in this order: name (600, Ink), date line (Label Gray), two short sentences (Body Ink), requirements (Label Gray), then the button and quiet link 2rem below.

### Step Labels
A row of numbered labels on the bare wall. Each has a 1px Hairline rule on top, 1rem above the text, a plain counter number in Label Gray with tabular figures, the title in Ink at 600 on its own line, then one or two sentences in Label Gray.

### Hung Work
A real screenshot of the app, not a mockup. It's shown at its true size or a little under, with the spotlight behind it and the Hung Work shadow under it. On load the spotlight fades up once over 1400ms (`cubic-bezier(0.16, 1, 0.3, 1)`, 120ms delay). With reduced motion it's already lit.

### Navigation
Blume's header, themed by tokens: the icon and "Closeup" on the left, Docs and GitHub on the right.

## Do's and Don'ts

### Do:
- **Do** keep Lens Indigo on things that act: buttons, links, focus, selection.
- **Do** build hierarchy on the landing page with weight (400 and 600) and ink (Ink, Body Ink, Label Gray) at one size.
- **Do** show the real app at its real size, lit from above with the Hung Work or Hung Figure shadow.
- **Do** cast every shadow straight down, and switch the contact shadow to the 1px white rim in dark mode.
- **Do** theme docs pages through tokens only and leave Blume's layout alone.
- **Do** let the spotlight come up once on load and skip it under reduced motion.

### Don't:
- **Don't** use a dark gradient SaaS hero, a centered headline over a device mockup, or a warm gray type poster.
- **Don't** add badges, chips, icon tiles or any gradient other than the spotlight.
- **Don't** put a screenshot in a device frame or a box; its own corners are its shape.
- **Don't** use indigo for decoration, headings, rules or backgrounds.
- **Don't** add a second accent color, in either mode.
