---
type: log
summary: Changed - every app's ship now builds in a build slot, from the checkout Deckhand hands it, with no private worktree or marker file; Mac apps install staged on batched and evening ships and reopen in the background otherwise, and the rules stop agents from shipping and restarting after each change.
project: android-webcam
sprint: syscleanup-7-apps-ship-lighter
window: 2026-10-30T21:28:06Z/2026-10-30T21:44:28Z
tickets: [android-webcam#j8yc]
---

# Systems cleanup 7: apps ship lighter

Changed: every app's ship now builds in a build slot, from the checkout Deckhand hands it, with no private worktree or marker file; Mac apps install staged on batched and evening ships and reopen in the background otherwise, and the rules stop agents from shipping and restarting after each change.
Try: not tried yet. Each app's next ship is the test: ship Ramble, Flare or Vesper from Deck and check it reopens without coming to the front.

## What changed

- A ship reopens Closeup in the background and leaves it running on a staged ship (android-webcam#j8yc)

## Calls

- A ship reopens Closeup only when it was running before the ship; a ship while it's closed leaves it closed. (android-webcam#j8yc)

## Needs you

- The rules change is committed in the dotfiles repo but not pushed (it's 18 commits ahead of its remote, and a sprint doesn't push).
