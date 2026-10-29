import { defineConfig } from "blume";

// Timeless Sans (Timeless Free Font License 1.2, timeless.co/type/license), self-hosted.
const timelessSans = [
  { src: "fonts/TimelessSans-Regular.woff2", weight: 400 },
  { src: "fonts/TimelessSans-Medium.woff2", weight: 500 },
  { src: "fonts/TimelessSans-Semibold.woff2", weight: 600 },
  { src: "fonts/TimelessSans-Bold.woff2", weight: 700 },
  { src: "fonts/TimelessSans-Black.woff2", weight: 800 },
];

export default defineConfig({
  title: "Closeup",
  description:
    "Use your Android phone's camera as your Mac's webcam, over USB or Wi-Fi. No app on the phone, no account and no cloud.",
  logo: { image: "/icon.svg", text: "Closeup" },

  content: {
    root: "content",
  },

  theme: {
    accent: { light: "#C23A1C", dark: "#FF8757" },
    background: { light: "#F5F5F2", dark: "#0D0C12" },
    radius: "md",
    mode: "system",
    fonts: {
      display: { name: "Timeless Sans", fallback: "sans", variants: timelessSans },
      body: { name: "Timeless Sans", fallback: "sans", variants: timelessSans },
      mono: "geist-mono",
    },
  },

  navigation: {
    actions: [
      { href: "/introduction", label: "Docs" },
      { href: "https://github.com/hkay-dev/closeup", label: "GitHub" },
    ],
  },

  markdown: {
    externalLinks: true,
    code: {
      theme: { light: "github-light", dark: "vesper" },
    },
  },

  github: {
    owner: "hkay-dev",
    repo: "closeup",
    dir: "site",
  },

  footer: {
    copyright: "© 2026 Harsha Kotcherlakota. Apache-2.0.",
    links: [
      { label: "Releases", href: "https://github.com/hkay-dev/closeup/releases" },
      { label: "Report a problem", href: "https://github.com/hkay-dev/closeup/issues" },
    ],
  },

  feedback: false,
});
