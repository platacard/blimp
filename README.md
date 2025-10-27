# <img width="45" alt="blimp_icon_dark" src="https://github.com/user-attachments/assets/d78717f8-c440-424f-a5ed-aae73747c128" /> Blimp
<!-- ALL-CONTRIBUTORS-BADGE:START - Do not remove or modify this section -->
[![All Contributors](https://img.shields.io/badge/all_contributors-3-orange.svg?style=flat-square)](#contributors-)
<!-- ALL-CONTRIBUTORS-BADGE:END -->

Finally, a Swift deployment automation for Apple platforms.

Heavily inspired by [fastlane](https://fastlane.tools/).

> Blimp refers to a non-rigid flying ship (like a zeppelin). Rarely used nowadays, it might be slow and clumsy, but still beautiful and gets the job done.

## Disclaimer

This project is still a work in progress but aims to be a native Swift `fastlane` replacement in the future. However, the implementation is already stable enough for Plata to ship our apps with it. If you have questions or issues, just open an issue/discussion and we'll try to help. If you want to contribute, feel free to open a pull request. Although it's better to align with our [roadmap](https://github.com/orgs/platacard/projects/3).

----

## Installation

As package dependency:
```swift
dependencies: [
    .package(url: "https://github.com/platacard/blimp.git", from: "1.0.0")
]
```

## Features overview

### What's working

- Archiving and exporting the iOS app
- Authenticating with the App Store Connect API
- Uploading iOS apps to App Store Connect and waiting for processing
- Assigning beta groups and sending builds for review
- Inviting developers and beta testers to TestFlight

### What's yet to be implemented

- Managing provisioning profiles and certificates. For now, we use an isolated [match](https://docs.fastlane.tools/actions/match/) part of fastlane.
- Uploading using App Store Connect’s latest API v4.1 (currently using `altool`)
- Testing support for watchOS, macOS, and other less-used platforms

----

## Getting started

Blimp is meant to be a building block in your pipeline, not a final, opinionated solution. It is best used in combination with other packages:

- [cronista](https://github.com/platacard/cronista) — A simple logger
- [corredor](https://github.com/platacard/corredor) — A shell wrapper
- [gito](https://github.com/platacard/gito) — A git wrapper
- [slackito](https://github.com/platacard/slackito) — A Slack API client using result builders
- [dotcontext](https://github.com/platacard/dotcontext) — An environment variables manager that extends .env file functionality

These packages provide a modular way to build your deploy pipeline. But the best part is that they are not required to use blimp. Tweak everything to your liking.

You can try things out by calling the `blimp` CLI via `swift run blimp {command}`, or you can compile the project and use the binary artifact directly.
 
>❗️ Moreover, `blimp` CLI provides an example of how you can use `BlimpKit` in your CLI. We recommend trying out the `swift-argument-parser` package, it works great for us.

You'll need the [App Store Connect API Key](https://developer.apple.com/documentation/appstoreconnectapi/creating_api_keys_for_app_store_connect_api). `blimp` will handle the API authentication process for you once the `.p8` file is placed in the `~/.appstoreconnect/private_keys` folder. Currently, uploads use `altool`, but we plan to migrate to the App Store Connect API (API uploads), which will enable authentication via environment variables and simplify CI integration. You can track progress on this feature in our [roadmap](https://github.com/orgs/platacard/projects/3).

Then, expose these environment variables to your shell:

```bash
export APP_STORE_CONNECT_API_KEY=...
export APP_STORE_CONNECT_API_KEY_ISSUER_ID=...
```

You can get these values from the App Store Connect API Keys page.

Using binary artifact:
```bash
swift build -c release
```

Then, you can use the binary artifact directly:
```bash
./build/release/blimp {command}
```

### Available commands

> Use -h with each command to see all available parameters and their default values.

1. `blimp takeoff {params}` - Archive the project
2. `blimp approach {params}` - Upload the archive to App Store Connect
3. `blimp land {params}` - Assign the build's beta groups and send it to external review
4. `blimp hangar {subcommand} {params}` - A set of commands to interact with provisioning profiles, see app size, etc.

## Architecture overview

`blimp` aims to keep its dependencies to a minimum. It uses Apple's OpenAPI generator to create App Store Connect API clients. Swift Crypto is used for JWT signing. Swift Argument Parser is used for the command line interface implementation. Finally, our own `cronista` and `corredor` are used for logging and calling CLI tools.

- Archiving and exporting are done via `xcodebuild`.
- Uploading is done via `altool`.
- Processing is done via the App Store Connect API.

## Attributions

JWT signing was borrowed from [AvdLee](https://github.com/AvdLee/appstoreconnect-swift-sdk) under MIT License.

## Contributors ✨

Thanks goes to these wonderful people ([emoji key](https://allcontributors.org/docs/en/emoji-key)):

<!-- ALL-CONTRIBUTORS-LIST:START - Do not remove or modify this section -->
<!-- prettier-ignore-start -->
<!-- markdownlint-disable -->
<table>
  <tbody>
    <tr>
      <td align="center" valign="top" width="14.28%"><a href="https://github.com/memoto"><img src="https://avatars.githubusercontent.com/u/16154570?v=4?s=100" width="100px;" alt="Konstantin Iurichev"/><br /><sub><b>Konstantin Iurichev</b></sub></a><br /><a href="https://github.com/platacard/blimp/commits?author=memoto" title="Code">💻</a></td>
      <td align="center" valign="top" width="14.28%"><a href="https://github.com/tigati"><img src="https://avatars.githubusercontent.com/u/2447006?v=4?s=100" width="100px;" alt="tigati"/><br /><sub><b>tigati</b></sub></a><br /><a href="https://github.com/platacard/blimp/commits?author=tigati" title="Code">💻</a></td>
      <td align="center" valign="top" width="14.28%"><a href="https://github.com/NoFearJoe"><img src="https://avatars.githubusercontent.com/u/4526841?v=4?s=100" width="100px;" alt="Ilya Kharabet"/><br /><sub><b>Ilya Kharabet</b></sub></a><br /><a href="https://github.com/platacard/blimp/commits?author=NoFearJoe" title="Code">💻</a></td>
    </tr>
  </tbody>
</table>

<!-- markdownlint-restore -->
<!-- prettier-ignore-end -->

<!-- ALL-CONTRIBUTORS-LIST:END -->

This project follows the [all-contributors](https://github.com/all-contributors/all-contributors) specification. Contributions of any kind welcome!
