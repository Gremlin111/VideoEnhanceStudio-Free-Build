# Video Enhance Studio — FREE Windows-to-iPad build

This package contains **source code**, not a compiled IPA. You do **not** need a paid Apple Developer membership or your own Mac. A free GitHub account builds the iPad app using a hosted Mac. Free Sideloadly on Windows signs the resulting IPA with your existing Apple ID and installs it on your iPad.

## 1. Put the source on GitHub (Windows)

1. Sign up for a free account at https://github.com if needed.
2. Install **GitHub Desktop** from https://desktop.github.com . Sign in.
3. Extract the `VideoEnhanceStudio-Free-Windows-to-iPad.zip` archive into a folder. Do not leave the code inside the ZIP.
4. Open GitHub Desktop: **File > Add local repository**, choose the extracted `VideoEnhanceStudio-Free-Build` folder. If it says this isn't a Git repository, choose **create a repository here**.
5. In GitHub Desktop, click **Publish repository**. You can use a **public repository** to avoid limited private-repository compute allowances. Public means others can view your app's *source code*, but **not** your private videos or Apple ID (neither is in this package). You may choose private if your plan's included Mac minutes are sufficient.

## 2. Build your IPA in GitHub (no Mac necessary)

1. Open your GitHub repository in the browser.
2. Click **Actions** > **Build free unsigned iPad IPA** > **Run workflow**.
3. When the run finishes successfully, open the workflow run and download the `VideoEnhanceStudio-unsigned-IPA` artifact under **Artifacts**.
4. Unzip the downloaded artifact ZIP. Inside is `VideoEnhanceStudio-unsigned.ipa`. Do NOT extract the IPA itself.
5. If compilation fails, open the workflow run's error log, or download `VideoEnhanceStudio-build-log` and share the first compiler error. The build has not been tested on an Apple-hosted runner yet.

## 3. Install the IPA using Windows and your free Apple ID

1. Download Sideloadly **only** from https://sideloadly.io . Its official guide notes it requires **non-Microsoft Store** editions of Apple's iTunes/iCloud software on Windows.
2. Connect the unlocked iPad via USB-C data cable and tap **Trust This Computer**, if prompted.
3. Open Sideloadly, select the iPad, drag in `VideoEnhanceStudio-unsigned.ipa`, enter your Apple ID, and press **Start**. No paid Apple Developer membership is needed.
4. On the iPad, follow device prompts to enable **Developer Mode** (Settings > Privacy & Security), restart if prompted, and trust the personal development certificate as needed under Settings > General > VPN & Device Management.
5. Launch Video Enhance Studio. Tap the AI model install button once with internet access; thereafter model inference runs on-device.

## Free-account limitations

- Apple free signing lasts **7 days**, after which the app needs refreshing. Sideloadly offers a daemon to refresh on Windows while the iPad is reachable.
- Free accounts allow a maximum of **3 sideloaded apps** installed at a time.
- The GitHub build generates an **unsigned IPA** intentionally; it is **not** something you can install just by tapping it on the iPad.
- **No cloud video processing**. The GitHub-hosted computer receives only the app's source code. Your personal video stays on the iPad and is processed locally after model download.
- **Not yet verified:** A real Xcode build, installation, model-download reliability, and performance on an M3 iPad. GitHub's Actions error logs are the next definitive diagnostic if the build fails.

## Project files

- `VideoEnhanceStudioApp/*.swift`: complete SwiftUI/Core ML / AVFoundation source from version 2.3.
- `project.yml`: XcodeGen project descriptor for building on a hosted Mac.
- `.github/workflows/build-ipad.yml`: a manually triggered GitHub Actions workflow that compiles an unsigned iPad app and uploads an IPA.

## Official or primary references

- Apple free developer account limits: https://developer.apple.com/help/account/basics/about-your-developer-account/
- Sideloadly Windows tool and free signing: https://sideloadly.io/
- XcodeGen project specification: https://github.com/yonaskolb/XcodeGen/blob/master/Docs/ProjectSpec.md
- GitHub-hosted runners: https://docs.github.com/en/actions/reference/runners/github-hosted-runners
