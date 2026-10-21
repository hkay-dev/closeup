---
type: log
summary: Two small tickets - a way back into the app when its menu bar icon is out of reach, and proof that the OBS check stays idle once setup is done.
project: android-webcam
sprint: android-webcam-menu-bar-way-in-and-a-lighter-obs-check
window: 2026-10-21T12:36:01Z/2026-10-21T13:07:25Z
tickets: [android-webcam#8tap, android-webcam#da0t]
---

# Android Webcam: menu bar way in and a lighter OBS check

Two small tickets: a way back into the app when its menu bar icon is out of reach, and proof that the OBS check stays idle once setup is done. Both are built; the reopen fix waits on your eyes.

## Patch notes

- Fixed: Opening Android Webcam again from Finder, Spotlight or Raycast used to do nothing when its icon was behind the notch or the menu bar was hidden. Now it opens the menu, or Settings when the icon can't be reached. Built, not tried on screen yet (android-webcam#8tap, 0382950)
- Under the hood: Every OBS extension lookup now writes a counted log line, and an idle run showed one lookup at launch and none after, so the 3 second check really does stop once setup is done (android-webcam#da0t, 1cb33bc)

## Waits on you

- android-webcam#8tap, Test it: open the app again with the icon showing, then with the menu bar set to hide or the icon behind the notch

## Where it landed

- android-webcam#8tap No way into the app when its menu bar icon is hidden: Test it, built and waiting for your check (0382950)
- android-webcam#da0t OBS extension check runs every 3 seconds after setup is done: Done, in the dev build (1cb33bc)

## Calls

- Worked 8tap as a grind fix (applicationShouldHandleReopen) under grind rules, not as a bug-bash charter that only files bugs, since the ticket is one clear bug with its fix written in (android-webcam#8tap)
- Worked da0t under grind rules (runtime proof plus a lookup log), not polish, since nothing on screen changes (android-webcam#da0t)
- Reopen counts the icon reachable from its window's visibility, occlusion and screen and notch-strip geometry, not statusItem.isVisible, which stays true when macOS hides the icon (android-webcam#8tap)
- Lookup proof is an os.Logger info line with a running count (subsystem com.harsha.android-webcam, category obs-lookup), not an os_signpost, so log stream can count it (android-webcam#da0t)

## Set aside

- android-webcam#rcbj: the build fails with the Mac's selected Command Line Tools toolchain in Settings' launch at login toggle, so this sprint built with the Xcode beta. Filed as a Ready bug for a later grind.
