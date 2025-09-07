<img src="https://batchclipboard.bananameter.lol/img/banner.png" alt="Logo"/>

[![Build Status](https://github.com/jpmhouston/Batch-Clipboard/actions/workflows/build.yml/badge.svg)](https://github.com/jpmhouston/Batch-Clipboard/actions/workflows/build.yml)
[![Downloads](https://img.shields.io/github/downloads/jpmhouston/Batch-Clipboard/total.svg)](https://github.com/jpmhouston/Batch-Clipboard/releases/latest)
[![Donate](https://img.shields.io/badge/buy%20me%20a%20coffee-donate-yellow.svg)](https://www.buymeacoffee.com/bananameterlabs)

Batch Clipboard is a menu bar utility for macOS that adds the ability to copy a "batch" of
multiple items at once, then paste them in the same order.

## About

Batch Clipboard is a clipboard utility that isn't intending to have all
the capabilities of a full-featured clipboard history manager, but to provide
just this single multi-clipboard feature:

<kbd>CONTROL (^)</kbd> + <kbd>COMMAND (⌘)</kbd> + <kbd>C</kbd> to copy as many items as
you like from a source document, then  
<kbd>CONTROL (^)</kbd> + <kbd>COMMAND (⌘)</kbd> + <kbd>V</kbd> to paste each item in the
same order into your target document.

[Full documentation is here](https://batchclipboard.bananameter.lol).

Batch Clipboard is built to run optimally on both Intel and Apple Silicon, and is intended
to work on systems running OS versions as old as 2019's macOS Catalina 10.15, however it
will run best on the latest OS (as of this writing, macOS 15 Sequoia).

_Testing has not been comprehensive on those older systems, please report any issues to
[batchclipboard.support@bananameter.lol](mailto:batchclipboard.support@bananameter.lol).  
Also, the app does not yet include any UI optimization for macOS 26 Tahoe, but that will be
released shortly after that operating system's release._

## Install

### Download from GitHub

There will always be a free download on this repo's
[releases page](https://github.com/jpmhouston/Batch-Clipboard/releases/latest) with the
complete and unrestricted functionality mentioned above, and more.

Download either the .zip or .dmg file. For the zip file, double-click to uncompress, drag
"Batch Cipboard.app" that results to /Applications (or wherever you decide to store your
installed applications).

For the disk image (dmg), double-click to mount and open its window, drag "Batch Cipboard.app"
in that window to /Applications, eject the disk image (in the Finder window sidebar, or
right-click and choose "Eject"), and finally trash the dmg file.

The GitHub edition of Batch Clipboard will notify you of future updates, controlled by an
option in the Settings window. Updates can be downloaded and applied easily, directly
from those notification alerts.
Future betas of the GitHub edition may be available, and the option to be notified of these
beta versions can also be found in the Settings window.

### Install from the Mac App Store

The app is also available for no cost on the Mac App Store
[here](https://apps.apple.com/app/batch-clipboard/id6695729238) with the same features as
the free GitHub edition. The Mac App Store edition, however, has an in-app purchase allowing
users to support future development and unlocks few bonus features. Read more about those
bonus features [in the documenentaion](https://batchclipboard.bananameter.lol/App-Store-Version-Differences/).

Future betas of the App Store edition may be available from its TestFlight
[page](ttps://testflight.apple.com/join/epg3cusH), but we don't guarentee there will always
be a beta available that hasn't expired.

### Install with Homebrew

As long as this app is hosted on a repo that's a fork of Maccy, Batch Clipboard cannot be
added to default homebrew tap. For the time being, you need to utilize the Bananameter Labs
tap to get the app as a homebrew cask:

```bash
brew install jpmhouston/bananameterlabs/batch-clipboard
```

or

```bash
brew tap jpmhouston/bananameterlabs
brew install batch-clipboard
```

At some point, the application may be available without referencing or adding the tap,
please use the Star or Watch buttons at the top of the [GitHub page](https://github.com/jpmhouston/Batch-Clipboard)
for this repo to help make this possible. Thank you!

### Build yourself

You can clone the project and build yourself using Apple's Xcode developer tools. This
reproduces exactly what we do to release to GitHub and the Mac App Store (although we
use GitHub workflow scripts to also sign, notarize, upload, etc., those scripts can be
found in this repo [here](https://github.com/jpmhouston/Batch-Clipboard/tree/main/.github/workflows)).

Open the project file `Batch Clipboard.xcodeproj` in Xcode and choose the build scheme
"Batch Clipboard", and then `Product` menu > `Run` (ie. build and run). This will build
and launch an unsigned build of the app. To install for use a regular app in your system,
find "Batch Clipboard.app" among the build products (in the `Products` group when
Xcode's sidebar is in the Project navigator view), use `File` menu > `Show in Finder`
and copy this to your Applications folder. There may be hoops to jump through the first
time you lauuch this un-code signed, un-notarized app from the Finder.

And this build will use the Debug configuration rather than Release as these days it's
trickier to coax Xcode to do a release build and extract the resulting app. However,
there's not a significant difference between the these two build configurations.

Note: You should avoid turning on automtic Sparkle updates in the app settings when
using your own builds. You could also change the build setting in Xocde to disable Sparkle.
Do this by:

- opening the project itself at the top of the sidebar's Project navigator view
- select the "Batch Clipboard" target in the middle sidebar, select tab "Build Settings"
- find "Swift Compiler - Custom Flags"
- double click on the right side of the Debug line, in the popup window that appears
  remove `SPARKLE_UPDATES` line (optionally remove it from the Release line as well)

_Also note: the scheme "Batch Clipboard (MAS)" builds essentially the same app but with
mentions of bonus features and in-app purchases in the Intro window, and an added
Settings panel for making those in-app purchases. Purchasing these will not work in a
custom build._

Alternately you can build from the command line instead of the Xcode app. In a terminal
window, cd into the source directory and:

    xcodebuild clean build -scheme "Batch Clipboard" -configuration Release -derivedDataPath .
    ls -d "./Build/Products/Release/Batch Clipboard.app" # copy this to /Applications
    # to copy the app using the Finder reveal it using: open "./Build/Products/Release/"
    # feel free to use a derivedDataPath other than ".", then find the "Build" directory there

## About the Source Code, Organization etc

The project started as a fork of the open source clipboard manager [Maccy](https://maccy.app),
originally in the repo [https://github.com/jpmhouston/Cleepp](https://github.com/jpmhouston/Cleepp)
(this was the app's working name at the start of its development).

With that repo I was trying to keep in sync with Maccy so I could merge over bug fixes,
and so kept the same file structure, project file, and build targets.
I was also hoping to keep the original source buildable so that I could continue to run
Maccy's unit tests. It had a confusing second hierachy of files, in some cases overriding
the original, and others leveraging and extending them.

I was also considering maintaining Maccy's localizations, however after replacing or
discarding much of the user interface, this turned out to not be feasible. For the time
being the app contains only English UI. I will restart the app's localization sometime
in the future.

Upstream Maccy however changed significantly since early 2024, and so keeping that fork
in sync became a lost cause. This new repo is a refactor of that original fork, renaming
and simplifying many components.

Also, now that the repo isn't a fork, I'm able to provide the app as a homebrew cask
without a custom tap. Please use the Star or Watch buttons at the top of the
[GitHub page](https://github.com/jpmhouston/Batch-Clipboard) for this repo to help make
this possible. Thank you!


## Thank you & Acknowledgements

Please consider supporting development of this app by either the in-app purchase in the
App Store version, or with a [tip at buymeacoffee.com](https://www.buymeacoffee.com/bananameterlabs).
This would be greatly appreciated.

_Thanks of course to the creators of [Maccy](https://maccy.app) and its contributors. 
Please consider supporting the continued development of that upstream project with a
[donation to it also at buymeacoffee.com](https://www.buymeacoffee.com/p0deje)._

The Batch Clipboard icon was based on [Clipboard Icon](https://icon-icons.com/icon/clipboard/50424)
by [benjsperry](https://icon-icons.com/users/SIspiIUR5Ovh9CSybjNDC/icon-sets/).
Earlier animated GIF versions of the logo were created with [Drama](www.drama.app)
by Pixelcut, makers of [PaintCode](https://paintcode.app). I no longer use that animated
logo but still really like the stuff that make over there at Pixelcut. 

## License

[MIT](./LICENSE)
