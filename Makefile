TARGET := iphone:clang:latest:14.0
INSTALL_TARGET_PROCESSES = Spotify
ARCHS = arm64

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = Lyssna

REPO_SLUG ?= $(shell git remote get-url origin 2>/dev/null | sed -E 's|.*github\.com[:/]([^/]+/[^/.]+)(\.git)?$$|\1|')
REPO_SLUG_FINAL := $(if $(REPO_SLUG),$(REPO_SLUG),jaydenjcpy/EeveeSpotifyReincarnated)

BRANCH_NAME ?= $(shell git rev-parse --abbrev-ref HEAD 2>/dev/null)
BRANCH_NAME_FINAL := $(if $(BRANCH_NAME),$(BRANCH_NAME),Master)

$(shell mkdir -p Sources/Lyssna/Generated)
$(shell printf 'enum GeneratedConfig {\n    static let repoSlug = "%s"\n    static let branchName = "%s"\n}\n' "$(REPO_SLUG_FINAL)" "$(BRANCH_NAME_FINAL)" > Sources/Lyssna/Generated/RepoSlug.swift)

Lyssna_FILES = $(shell find Sources/Lyssna -name '*.swift') $(shell find Sources/LyssnaC -name '*.m' -o -name '*.c' -o -name '*.mm' -o -name '*.cpp')
Lyssna_FILES += Sources/LyssnaC/LyssnaOfflineArtistFollow.x
Lyssna_SWIFTFLAGS = -ISources/LyssnaC/include -Osize
Lyssna_EXTRA_FRAMEWORKS = LyssnaProtobuf
Lyssna_CFLAGS = -fobjc-arc -ISources/LyssnaC/include -Os

# RootHide's compatibility implementation of libroot resolves jailbreak paths
# through libroothide at runtime. Rootless builds continue to use libroot.
ifeq ($(THEOS_PACKAGE_SCHEME),roothide)
Lyssna_SWIFTFLAGS += -D ROOTHIDE
Lyssna_LDFLAGS += -lroothide -Xlinker -rpath -Xlinker @loader_path/.jbroot/Library/Frameworks
else
Lyssna_LDFLAGS += -lroot
endif

# Sideload compatibility (keychain redirect, group containers, CloudKit) is
# handled out-of-process by modules/zxPluginsInject — LC-injected via ipapatch
# in build-ipa-local.sh and the GitHub workflow. No flags needed here.

include $(THEOS_MAKE_PATH)/tweak.mk

internal-stage::
	# Bundle LyssnaProtobuf.framework into the package. Renamed from
	# SwiftProtobuf so the @objc class names don't collide with the
	# SwiftProtobuf statically embedded in SpotifyShared.framework.
	mkdir -p $(THEOS_STAGING_DIR)/Library/Frameworks
	cp -r $(THEOS)/lib/iphone/$(or $(THEOS_PACKAGE_SCHEME),rootless)/LyssnaProtobuf.framework $(THEOS_STAGING_DIR)/Library/Frameworks/
	# Ship the shader in the resource bundle so sideloaded IPAs retain it.
	xcrun -sdk iphoneos metal -c Sources/Lyssna/Karaoke/KaraokeBackgroundShader.metal \
		-o $(THEOS_OBJ_DIR)/KaraokeBackgroundShader.air
	xcrun -sdk iphoneos metallib $(THEOS_OBJ_DIR)/KaraokeBackgroundShader.air \
		-o "$(THEOS_STAGING_DIR)/Library/Application Support/Lyssna.bundle/KaraokeBackgroundShader.metallib"

# Build LyssnaProtobuf.framework from apple/swift-protobuf source. Run
# this once before `make package`. Re-run if SWIFTPROTOBUF_VERSION changes
# or `swift --version` jumps a major.
build-lyssnaprotobuf:
	Tools/SwiftProtobufBuild/build-lyssnaprotobuf.sh
