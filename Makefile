# Nexus Resonance - Cross-platform build
# Requires: Python 3, SCons 4+, platform toolchains (MSVC/gcc/clang, Android NDK for Android)

.PHONY: install-steam-audio build build-windows build-linux build-macos build-android build-ios ios-deps build-visionos build-visionos-simulator visionos-deps visionos-simulator-deps visionos-xcframeworks release help

# Install Steam Audio SDK (download from GitHub releases)
install-steam-audio:
	python3 scripts/install_steam_audio.py

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
	scons platform=macos arch=universal target=template_debug
	scons platform=macos arch=universal target=template_release

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

VISIONOS_BIN = addons/nexus_resonance/bin/visionos
VISIONOS_SIM_BIN = addons/nexus_resonance/bin/visionos_simulator
SCONS_FLAGS ?= -j4

visionos-deps: install-steam-audio
	mkdir -p $(VISIONOS_BIN)
	cp src/lib/steamaudio/lib/visionos/libphonon.a src/lib/steamaudio/lib/visionos/libpffft.a src/lib/steamaudio/lib/visionos/libmysofa.a $(VISIONOS_BIN)/

visionos-simulator-deps: install-steam-audio
	mkdir -p $(VISIONOS_SIM_BIN)
	cp src/lib/steamaudio/lib/visionos_simulator/libphonon.a src/lib/steamaudio/lib/visionos_simulator/libpffft.a src/lib/steamaudio/lib/visionos_simulator/libmysofa.a $(VISIONOS_SIM_BIN)/

build-visionos: visionos-deps
	scons platform=visionos arch=arm64 target=template_debug build_tests=0 $(SCONS_FLAGS)
	scons platform=visionos arch=arm64 target=template_release build_tests=0 $(SCONS_FLAGS)
	cp src/lib/godot-cpp/bin/libgodot-cpp.visionos.template_debug.arm64.a $(VISIONOS_BIN)/
	cp src/lib/godot-cpp/bin/libgodot-cpp.visionos.template_release.arm64.a $(VISIONOS_BIN)/

build-visionos-simulator: visionos-simulator-deps
	scons platform=visionos arch=arm64 visionos_simulator=yes target=template_debug build_tests=0 $(SCONS_FLAGS)
	scons platform=visionos arch=arm64 visionos_simulator=yes target=template_release build_tests=0 $(SCONS_FLAGS)
	cp src/lib/godot-cpp/bin/libgodot-cpp.visionos.template_debug.arm64.simulator.a $(VISIONOS_SIM_BIN)/
	cp src/lib/godot-cpp/bin/libgodot-cpp.visionos.template_release.arm64.simulator.a $(VISIONOS_SIM_BIN)/

visionos-xcframeworks:
	bash scripts/make_visionos_xcframeworks.sh $(VISIONOS_BIN) $(VISIONOS_SIM_BIN) addons/nexus_resonance/bin/visionos-xcframeworks

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
	@echo "  build-visionos       - Build visionOS arm64 using the pinned prebuilt SDK"
	@echo "  build-visionos-simulator - Build visionOS simulator arm64"
	@echo "  visionos-xcframeworks - Package both visionOS variants"
	@echo "  release             - Build all desktop platforms"
	@echo ""
	@echo "Manual SCons examples:"
	@echo "  scons platform=windows"
	@echo "  scons platform=linux"
	@echo "  scons platform=macos arch=arm64"
	@echo "  scons platform=android arch=arm64 target=template_release"
