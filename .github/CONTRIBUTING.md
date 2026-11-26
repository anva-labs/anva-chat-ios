# Contributing

This guide describes how to contribute to Anva Chat for iOS.

**Table of Contents**

* [What contributions are accepted](#what-contributions-are-accepted)
* [Build instructions](#build-instructions)
* [Working with upstream](#working-with-upstream)
* [How to get your pull request accepted](#how-to-get-your-pull-request-accepted)
  * [Keep your pull requests limited to a single issue](#keep-your-pull-requests-limited-to-a-single-issue)
  * [Don't mix code changes with whitespace cleanup](#dont-mix-code-changes-with-whitespace-cleanup)
  * [Keep your code simple!](#keep-your-code-simple)
  * [Test your changes!](#test-your-changes)
  * [Write a good commit message](#write-a-good-commit-message)

## What contributions are accepted

Use [Anva Chat issues][issues] to report bugs or discuss ideas for the agent messaging experience. For bugs, include your app version, iOS version, device or simulator, and the steps that reproduce the issue.

Submit changes to [Anva Chat][pr]. For a change that belongs in Telegram iOS itself, see the [upstream contribution guide][upstream-guide].

## Build instructions

See the [README.md][build_instructions] for details on the various build
environments.

## Working with upstream

Anva Chat is based on Telegram iOS. To compare against the latest Telegram iOS source, add it as a separate remote and fetch its `master` branch.

```sh
git remote add upstream https://github.com/TelegramMessenger/Telegram-iOS.git
git fetch upstream master
```

Use the Anva Chat branch you are targeting as the base for your change.

## How to get your pull request accepted

Keep your changes easy to review so we can keep Anva Chat stable for users.

### Keep your pull requests limited to a single issue

Pull requests should be as small/atomic as possible. Large, wide-sweeping changes in a pull request will be **rejected**, with comments to isolate the specific code in your pull request. Some examples:

* If you are making spelling corrections in the docs, don't modify other files.
* If you are adding new functions don't '*cleanup*' unrelated functions. That cleanup belongs in another pull request.

### Don't mix code changes with whitespace cleanup

If you change two lines of code and correct 200 lines of whitespace issues in a file the diff on that pull request is functionally unreadable and will be **rejected**. Whitespace cleanups need to be in their own pull request.

### Keep your code simple!

Please keep your code as clean and straightforward as possible.
Furthermore, the pixel shortage is over. We want to see:

* `opacity` instead of `o`
* `placeholder` instead of `ph`
* `myFunctionThatDoesThings()` instead of `mftdt()`

### Test your changes!

Before you submit a pull request, please test your changes. Describe what you verified, including the iOS version and whether you tested on a device or simulator.

### Write a good commit message

* Explain why you make the changes. [More infos about a good commit message.][commit_message]

* If you fix an issue with your commit, please close the issue by [adding one of the keywords and the issue number][closing-issues-via-commit-messages] to your commit message.

  For example: `Fix #545`

[//]: # (LINKS)
[commit_message]: http://tbaggery.com/2008/04/19/a-note-about-git-commit-messages.html
[issues]: https://github.com/anva-labs/anva-chat-ios/issues
[pr]: https://github.com/anva-labs/anva-chat-ios/compare
[upstream-guide]: https://github.com/TelegramMessenger/Telegram-iOS/blob/master/.github/CONTRIBUTING.md
[build_instructions]: ../README.md#build-from-source
[closing-issues-via-commit-messages]: https://help.github.com/articles/closing-issues-via-commit-messages/
