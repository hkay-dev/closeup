---
version: 1
slug: "site"
primary_target: "site"
related_targets: []
---

Scope: the Closeup docs site in `site/` (Blume). Landing page is Persuade; every docs page is Read.

Audience: Mac users with an Android phone who want it as a webcam, most of whom don't know adb, scrcpy or OBS. A short developer section covers building and internals.

Brief (2026-10-29, android-webcam#bt62): simple, elegant, clean, minimal; a fresh look replacing warm gray and orange; the real app leads the first screen; a few short points below; code-led build. Decision comp: `.impeccable/mocks/decision/assigned.png` (critique reference, not a spec).

## Direction contract

seed: seed:3a74d9de302f194b

THESIS: Closeup hung like a single work on a white gallery wall, with a small wall label beside it. Refuses the dark gradient SaaS hero, the centered headline over a device mockup, and the old warm-gray type poster.

OWN-WORLD: Matte gallery white wall (#F5F5F2) with near-black ink (#161616) and a gray for secondary label lines; dark mode is the same gallery after hours (#141414 wall). One indigo from the icon's lens (#3F3FB8 light, #9494F7 dark) used only on what acts: the Download button, links. One light source from above: a soft spotlight falloff on the wall and every shadow cast downward. Switzer (Fontshare) for all text; Geist Mono stays for code in the docs. No badges, chips, icon tiles or gradients beyond the light.

STORY: The visitor sees the real Live Controls panel at its true size, reads the wall label (name, what it is, what it needs, that it's free), and clicks Download for Mac, which goes to the install page. Below, four small labels in the order a first call happens: plug in, start, pick the camera, tune it.

FIRST VIEWPORT: A full-width wall under the nav. The Live Controls panel, true size (320 px wide, capped by viewport height), sits left of center; the wall label sits to its right on the panel's eye-line, about 22rem wide, one type size with hierarchy by weight and ink: "Closeup", the medium line "Android phone and Mac, 2026.", one short description, the requirements, then an indigo Download for Mac button and a Read the docs link.

FORM: Persuade landing on Blume's PageLayout, then Blume's three-column docs for Read pages, themed through tokens only. Below the fold: one row of four numbered labels on the same wall, then the footer.

SIGNATURE: The wall label as the call to action; on load the spotlight comes up once over the panel (reduced motion: already lit).
