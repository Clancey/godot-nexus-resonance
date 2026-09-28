# Nexus Resonance - Cross-platform build
# Requires: Python 3, SCons 4+, platform toolchains (MSVC/gcc/clang, Android NDK for Android)

.PHONY: install-steam-audio build build-windows build-linux build-macos build-android build-ios ios-deps build-visionos visionos-deps release help

# Install Steam Audio SDK (download from GitHub releases)
install-steam-audio:
	$(if $(wildcard src/lib/steamaudio/lib),\
		@echo "Steam Audio lib already present. Skipping.",\
		python3 scripts/install_steam_audio.py)

# Build for current/default platform
build: install-steam-audio
	scons

# Platform-specific builds
build-windows: install-steam-audio
	scons platform=windows target=template_debug
	scons platform=windows target=template_release

build-linux: install-steam-audio
	scons platform=linux target=template_debug
	scons platform=linux target=template_release

build-macos: install-steam-audio
	scons platform=macos target=template_debug
	scons platform=macos target=template_release

build-android: install-steam-audio
	scons platform=android arch=arm64 target=template_debug
	scons platform=android arch=arm64 target=template_release
	scons platform=android arch=x86_64 target=template_debug
	scons platform=android arch=x86_64 target=template_release

# iOS dependencies: build pffft and libmysofa as static libraries for arm64
ios-deps:
	mkdir -p addons/nexus_resonance/bin/ios
	# Build pffft for iOS arm64
	IOS_SDK=$$(xcrun --sdk iphoneos --show-sdk-path) && \
		xcrun --sdk iphoneos clang -arch arm64 -isysroot "$$IOS_SDK" -miphoneos-version-min=12.0 -O2 -DPFFFT_ENABLE_NEON \
			-Isrc/lib/pffft/include/pffft -c src/lib/pffft/src/pffft.c -o src/lib/pffft/src/pffft.o && \
		xcrun --sdk iphoneos clang -arch arm64 -isysroot "$$IOS_SDK" -miphoneos-version-min=12.0 -O2 -DPFFFT_ENABLE_NEON \
			-Isrc/lib/pffft/include/pffft -c src/lib/pffft/src/pffft_common.c -o src/lib/pffft/src/pffft_common.o && \
		ar rcs addons/nexus_resonance/bin/ios/libpffft.a src/lib/pffft/src/pffft.o src/lib/pffft/src/pffft_common.o
	# Build libmysofa for iOS arm64
	IOS_SDK=$$(xcrun --sdk iphoneos --show-sdk-path) && \
		cmake -S src/lib/libmysofa -B src/lib/libmysofa/build-ios \
			-DCMAKE_SYSTEM_NAME=iOS -DCMAKE_OSX_ARCHITECTURES=arm64 \
			-DCMAKE_OSX_DEPLOYMENT_TARGET=12.0 -DCMAKE_OSX_SYSROOT="$$IOS_SDK" \
			-DBUILD_TESTS=OFF -DBUILD_SHARED_LIBS=OFF && \
		cmake --build src/lib/libmysofa/build-ios --config Release
	cp src/lib/libmysofa/build-ios/src/libmysofa.a addons/nexus_resonance/bin/ios/

build-ios: install-steam-audio ios-deps
	scons platform=ios arch=arm64 target=template_debug
	scons platform=ios arch=arm64 target=template_release
	cp src/lib/godot-cpp/bin/libgodot-cpp.ios.template_debug.arm64.a addons/nexus_resonance/bin/ios/
	cp src/lib/godot-cpp/bin/libgodot-cpp.ios.template_release.arm64.a addons/nexus_resonance/bin/ios/

# visionOS dependencies. Valve ships no visionOS binaries, so Steam Audio itself (and the pffft,
# libmysofa and zlib it needs) is built from source for arm64 visionOS. STEAM_AUDIO_SRC must point
# to a Steam Audio checkout that has the visionOS build support (branch "visionos" of the fork).
# Needs CMake 3.28+; CMAKE_POLICY_VERSION_MINIMUM lets CMake 4 configure the older dependencies.
STEAM_AUDIO_SRC ?= ../steam-audio
VISIONOS_BIN = addons/nexus_resonance/bin/visionos

visionos-deps:
	test -f "$(STEAM_AUDIO_SRC)/core/build/toolchain_visionos.cmake"
	mkdir -p $(VISIONOS_BIN)
	cd "$(STEAM_AUDIO_SRC)/core/build" && CMAKE_POLICY_VERSION_MINIMUM=3.5 python3 get_dependencies.py -p visionos
	cd "$(STEAM_AUDIO_SRC)/core/build" && CMAKE_POLICY_VERSION_MINIMUM=3.5 python3 build.py -p visionos -c release --minimal -o ci_build
	cp "$(STEAM_AUDIO_SRC)/core/bin/lib/visionos/libphonon.a" $(VISIONOS_BIN)/
	cp "$(STEAM_AUDIO_SRC)/core/deps/pffft/lib/visionos/release/libpffft.a" $(VISIONOS_BIN)/
	cp "$(STEAM_AUDIO_SRC)/core/deps/mysofa/lib/visionos/release/libmysofa.a" $(VISIONOS_BIN)/
	cp "$(STEAM_AUDIO_SRC)/core/deps/zlib/lib/visionos/release/libz.a" $(VISIONOS_BIN)/

build-visionos: install-steam-audio visionos-deps
	scons platform=visionos arch=arm64 target=template_debug
	scons platform=visionos arch=arm64 target=template_release
	cp src/lib/godot-cpp/bin/libgodot-cpp.visionos.template_debug.arm64.a $(VISIONOS_BIN)/
	cp src/lib/godot-cpp/bin/libgodot-cpp.visionos.template_release.arm64.a $(VISIONOS_BIN)/

# Build all desktop platforms (Windows, Linux, macOS)
release: build-windows build-linux build-macos

help:
	@echo "Nexus Resonance Makefile"
	@echo ""
	@echo "Targets:"
	@echo "  install-steam-audio  - Download Steam Audio SDK binaries"
	@echo "  build               - Build for current platform"
	@echo "  build-windows        - Build Windows x64 (debug + release)"
	@echo "  build-linux          - Build Linux x64 (debug + release)"
	@echo "  build-macos          - Build macOS (debug + release)"
	@echo "  build-android        - Build Android arm64 + x86_64"
	@echo "  ios-deps            - Build pffft and libmysofa for iOS arm64"
	@echo "  build-ios            - Build iOS arm64 (debug + release)"
	@echo "  visionos-deps       - Build Steam Audio, pffft, libmysofa, zlib for visionOS arm64 (needs STEAM_AUDIO_SRC)"
	@echo "  build-visionos       - Build visionOS arm64 (debug + release)"
	@echo "  release             - Build all desktop platforms"
	@echo ""
	@echo "Manual SCons examples:"
	@echo "  scons platform=windows"
	@echo "  scons platform=linux"
	@echo "  scons platform=macos arch=arm64"
	@echo "  scons platform=android arch=arm64 target=template_release"
