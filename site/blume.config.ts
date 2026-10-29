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
    accent: { light: "#3F3FB8", dark: "#9494F7" },
    background: { light: "#F5F5F2", dark: "#141414" },
    radius: "md",
    mode: "system",
    fonts: {
      display: { name: "Switzer", provider: "fontshare", fallback: "sans", weights: [400, 500, 600] },
      body: { name: "Switzer", provider: "fontshare", fallback: "sans", weights: [400, 500, 600] },
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
