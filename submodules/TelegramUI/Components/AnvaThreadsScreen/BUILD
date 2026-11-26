load("@build_bazel_rules_swift//swift:swift.bzl", "swift_library")
load("@build_bazel_rules_apple//apple:ios.bzl", "ios_unit_test")
load("@build_bazel_rules_apple//apple/testing/default_runner:ios_test_runner.bzl", "ios_test_runner")

swift_library(
    name = "AnvaThreadsScreen",
    module_name = "AnvaThreadsScreen",
    srcs = glob([
        "Sources/**/*.swift",
    ]),
    copts = [
        "-warnings-as-errors",
    ],
    deps = [
        "//submodules/AsyncDisplayKit",
        "//submodules/Display",
        "//submodules/AppBundle",
        "//submodules/ComponentFlow",
        "//submodules/ContextUI",
        "//submodules/SSignalKit/SwiftSignalKit",
        "//submodules/AccountContext",
        "//submodules/TelegramCore",
        "//submodules/TelegramPresentationData",
        "//submodules/AvatarNode",
        "//submodules/LocalizedPeerData",
        "//submodules/SearchUI",
        "//submodules/SearchBarNode",
        "//submodules/TelegramUI/Components/ChatListHeaderComponent",
        "//submodules/TelegramUI/Components/NavigationBarComponent",
        "//submodules/TelegramUI/Components/SideColumnLayout",
    ],
    visibility = [
        "//visibility:public",
    ],
)

swift_library(
    name = "AnvaThreadsScreenTestsLib",
    testonly = True,
    srcs = glob([
        "Tests/**/*.swift",
    ]),
    deps = [
        ":AnvaThreadsScreen",
        "//submodules/SSignalKit/SwiftSignalKit",
        "//submodules/TelegramCore",
    ],
)

ios_test_runner(
    name = "AnvaThreadsScreenTestRunner",
    device_type = "iPhone 17",
    os_version = "26.5",
)

ios_unit_test(
    name = "AnvaThreadsScreenTests",
    minimum_os_version = "15.0",
    runner = ":AnvaThreadsScreenTestRunner",
    deps = [
        ":AnvaThreadsScreenTestsLib",
    ],
    visibility = [
        "//visibility:public",
    ],
)
