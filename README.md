# Anva Chat

**A better messenger for your agents, built on Telegram.**

Anva Chat is an unofficial iOS client based on Telegram iOS. It gives the Telegram bots that your agents use a dedicated Home tab so you can start a task in its own thread, find an earlier reply, and share context from another app.

## Working with your agents

- **Find your conversations.** Home brings bot conversations together. Search messages, pin threads you use often, and mark conversations as read.
- **Give each task its own thread.** Use a bot that supports user-managed Telegram topics to keep tasks separate. Open a new thread from the chat menu or Control Center.
- **Share context from iOS.** Pick a compatible bot from the suggested conversations in the iOS share sheet to open a new thread draft with a link or photos. Review the draft before sending.

To get started, sign in with your Telegram account and send a message to the Telegram bot connected to your agent. Anva Chat is the messaging client. Your agent runs wherever you host it.

## Build from source

### Get the code

```
git clone --recurse-submodules https://github.com/anva-labs/anva-chat-ios.git
cd anva-chat-ios
```

### Set up Xcode

Install Xcode and select the version pinned in [versions.json](versions.json). The build uses Bazel through the repository's `Make.py` wrapper. See [CLAUDE.md](CLAUDE.md) for the supported build and test commands.

### Set up your build configuration

1. Copy [the development configuration template](build-system/template_minimal_development_configuration.json) to `$HOME/anva-chat-development.json`.
2. Obtain your own Telegram API ID and API hash and add them to the local configuration. [Telegram API registration guide](https://core.telegram.org/api/obtaining_api_id)
3. Choose a unique bundle identifier and add your Apple Developer Team ID. Keep API credentials and signing material local.

### Generate an Xcode project

```
python3 build-system/Make/Make.py \
    --cacheDir="$HOME/telegram-bazel-cache" \
    generateProject \
    --configurationPath="$HOME/anva-chat-development.json" \
    --xcodeManagedCodesigning
```

## Advanced builds

### Xcode

1. Copy and edit `build-system/appstore-configuration.json`.
2. Copy `build-system/fake-codesigning`. Create and download provisioning profiles, using the `profiles` folder as a reference for the entitlements.
3. Generate an Xcode project:
```
python3 build-system/Make/Make.py \
    --cacheDir="$HOME/telegram-bazel-cache" \
    generateProject \
    --configurationPath=configuration_from_step_1.json \
    --codesigningInformationPath=directory_from_step_2
```

### IPA

1. Repeat the steps from the previous section. Use distribution provisioning profiles.
2. Run:
```
python3 build-system/Make/Make.py \
    --cacheDir="$HOME/telegram-bazel-cache" \
    build \
    --configurationPath=...see previous section... \
    --codesigningInformationPath=...see previous section... \
    --buildNumber=100001 \
    --configuration=release_arm64
```

## FAQ

### Xcode is stuck at "build-request.json not updated yet"

Occasionally, you might observe the following message in your build log:
```
"/Users/xxx/Library/Developer/Xcode/DerivedData/Telegram-xxx/Build/Intermediates.noindex/XCBuildData/xxx.xcbuilddata/build-request.json" not updated yet, waiting...
```

Should this occur, simply cancel the ongoing build and initiate a new one.

### Telegram_xcodeproj: no such package

Following a system restart, the auto-generated Xcode project might encounter a build failure accompanied by this error:
```
ERROR: Skipping '@rules_xcodeproj_generated//generator/Telegram/Telegram_xcodeproj:Telegram_xcodeproj': no such package '@rules_xcodeproj_generated//generator/Telegram/Telegram_xcodeproj': BUILD file not found in directory 'generator/Telegram/Telegram_xcodeproj' of external repository @rules_xcodeproj_generated. Add a BUILD file to a directory to mark it as a package.
```

If you encounter this issue, re-run the project generation steps in the README.


## Tips

### Codesigning is not required for simulator-only builds

Add `--disableProvisioningProfiles`:
```
python3 build-system/Make/Make.py \
    --cacheDir="$HOME/telegram-bazel-cache" \
    generateProject \
    --configurationPath=path-to-configuration.json \
    --xcodeManagedCodesigning \
    --disableProvisioningProfiles
```

### Versions

Each release is built using a specific Xcode version (see `versions.json`). The helper script checks the versions of the installed software and reports an error if they don't match the ones specified in `versions.json`. It is possible to bypass these checks:

```
python3 build-system/Make/Make.py --overrideXcodeVersion build ... # Don't check the version of Xcode
```

## Contributing and upstream

For changes to Anva Chat, see the [contribution guide](.github/CONTRIBUTING.md).

Anva Chat builds on [Telegram iOS](https://github.com/TelegramMessenger/Telegram-iOS). The upstream project maintains [Telegram API security guidelines](https://core.telegram.org/mtproto/security_guidelines) for client developers.

## License and copyright

Anva Chat is distributed under the GNU General Public License, version 2 or any later version (`GPL-2.0-or-later`). See [LICENSE](LICENSE) for the full terms and [Telegram's source code page](https://telegram.org/apps#source-code) for the upstream license.

Copyright in Telegram iOS belongs to its original copyright holders. Copyright in Anva Chat contributions belongs to their respective contributors. Third-party components retain the copyright and license notices provided with their sources.
