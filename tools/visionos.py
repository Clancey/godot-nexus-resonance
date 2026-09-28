"""SCons platform tool for Apple visionOS (Vision Pro).

godot-cpp ships tools for linux/macos/windows/android/ios/web only, so this one is
loaded through godot-cpp's `custom_tools` option (the top level SConstruct sets that
automatically for platform=visionos). It is modelled on godot-cpp's tools/ios.py.
"""

import codecs
import os
import subprocess
import sys

import common_compiler_flags
from SCons.Variables import BoolVariable


def options(opts):
    opts.Add(BoolVariable("visionos_simulator", "Target the visionOS Simulator", False))
    opts.Add("visionos_min_version", "Target minimum visionOS version", "2.0")
    opts.Add(
        "VISIONOS_TOOLCHAIN_PATH",
        "Path to the Xcode toolchain",
        "/Applications/Xcode.app/Contents/Developer/Toolchains/XcodeDefault.xctoolchain",
    )
    opts.Add("VISIONOS_SDK_PATH", "Path to the visionOS SDK", "")


def exists(env):
    return sys.platform == "darwin"


def generate(env):
    if env["arch"] != "arm64":
        raise ValueError("Only arm64 is supported on visionOS. Exiting.")

    if env["visionos_simulator"]:
        sdk_name = "xrsimulator"
        target = "arm64-apple-xros" + env["visionos_min_version"] + "-simulator"
        # godot-cpp appends ".simulator" to the library suffix when this is set.
        env["ios_simulator"] = True
    else:
        sdk_name = "xros"
        target = "arm64-apple-xros" + env["visionos_min_version"]

    if env["VISIONOS_SDK_PATH"] == "":
        try:
            env["VISIONOS_SDK_PATH"] = codecs.utf_8_decode(
                subprocess.check_output(["xcrun", "--sdk", sdk_name, "--show-sdk-path"]).strip()
            )[0]
        except (subprocess.CalledProcessError, OSError):
            raise ValueError("Failed to find SDK path while running xcrun --sdk {} --show-sdk-path.".format(sdk_name))

    compiler_path = env["VISIONOS_TOOLCHAIN_PATH"] + "/usr/bin/"
    env["CC"] = compiler_path + "clang"
    env["CXX"] = compiler_path + "clang++"
    env["AR"] = compiler_path + "ar"
    env["RANLIB"] = compiler_path + "ranlib"
    env["SHLIBSUFFIX"] = ".dylib"
    env["ENV"]["PATH"] = env["VISIONOS_TOOLCHAIN_PATH"] + "/Developer/usr/bin/:" + env["ENV"]["PATH"]

    # visionOS has no -m<os>-version-min flag that every clang accepts; the target triple
    # carries both the platform and the minimum OS version.
    env.Append(CCFLAGS=["-target", target, "-isysroot", env["VISIONOS_SDK_PATH"]])
    env.Append(LINKFLAGS=["-target", target, "-isysroot", env["VISIONOS_SDK_PATH"], "-F" + env["VISIONOS_SDK_PATH"]])

    env.Append(CPPDEFINES=["VISIONOS_ENABLED", "APPLE_EMBEDDED_ENABLED", "UNIX_ENABLED"])

    # Same reasoning as iOS: LTO makes the final link in Xcode very slow.
    if env["lto"] == "auto":
        env["lto"] = "none"

    common_compiler_flags.generate(env)
