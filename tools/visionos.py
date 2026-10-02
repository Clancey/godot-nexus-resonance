"""visionOS device/simulator tool loaded by godot-cpp's custom_tools option."""
import subprocess
import sys

import common_compiler_flags
from SCons.Variables import BoolVariable


def options(opts):
    opts.Add(BoolVariable("visionos_simulator", "Target the visionOS Simulator", False))
    opts.Add("visionos_min_version", "Minimum visionOS version (SDK requires 2.0)", "2.0")
    opts.Add("VISIONOS_SDK_PATH", "Override the visionOS SDK path", "")


def exists(env):
    return sys.platform == "darwin"


def generate(env):
    if env["arch"] != "arm64":
        raise ValueError("visionOS requires arch=arm64")
    if tuple(int(part) for part in env["visionos_min_version"].split(".")) < (2, 0):
        raise ValueError("The Steam Audio SDK requires visionOS 2.0 or newer")
    simulator = env["visionos_simulator"]
    sdk = "xrsimulator" if simulator else "xros"
    target = "arm64-apple-xros" + env["visionos_min_version"] + ("-simulator" if simulator else "")
    env["ios_simulator"] = simulator
    if not env["VISIONOS_SDK_PATH"]:
        env["VISIONOS_SDK_PATH"] = subprocess.check_output(
            ["xcrun", "--sdk", sdk, "--show-sdk-path"], text=True
        ).strip()
    for variable, tool in (("CC", "clang"), ("CXX", "clang++"), ("AR", "ar"), ("RANLIB", "ranlib")):
        env[variable] = subprocess.check_output(["xcrun", "--sdk", sdk, "--find", tool], text=True).strip()
    env["SHLIBSUFFIX"] = ".dylib"
    flags = ["-target", target, "-isysroot", env["VISIONOS_SDK_PATH"]]
    env.Append(CCFLAGS=flags, LINKFLAGS=flags)
    env.Append(CPPDEFINES=["VISIONOS_ENABLED", "APPLE_EMBEDDED_ENABLED", "UNIX_ENABLED"])
    if env["lto"] == "auto":
        env["lto"] = "none"
    common_compiler_flags.generate(env)
