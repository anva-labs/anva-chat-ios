load("@build_bazel_rules_swift//swift:swift.bzl", "swift_library")

exports_files(["AnvaNewThreadIntent.swift"], visibility = ["//Telegram:__pkg__"])

swift_library(
    name = "AnvaNewThreadIntentWidget",
    module_name = "AnvaNewThreadIntents",
    srcs = ["AnvaNewThreadIntent.swift"],
    linkopts = ["-Wl,-weak_framework,AppIntents"],
    visibility = ["//Telegram:__pkg__"],
)
