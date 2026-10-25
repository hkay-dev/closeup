import { defineConfig } from "blume";

export default defineConfig({
  title: "Closeup",
  description:
    "Use your Android phone's camera as your Mac's webcam, over USB or Wi-Fi. No app on the phone, no account and no cloud.",
  logo: { image: "/icon.svg", text: "Closeup" },

  content: {
    root: "content",
  },

  theme: {
    accent: { light: "#B8420A", dark: "#F06418" },
    background: { light: "#F2F0EC", dark: "#1A1917" },
    radius: "lg",
    mode: "system",
    fonts: {
      display: "geist",
      body: "geist",
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
