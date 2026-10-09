THEOS_DEVICE_IP ?=

# ── Project Identity ─────────────────────────────────────────────────────────
INSTALL_TARGET_PROCESSES = Roblox RobloxPlayer

include $(THEOS)/makefiles/common.mk

# ── Tweak Target ─────────────────────────────────────────────────────────────
TWEAK_NAME = LARPTool

# ── Sources ──────────────────────────────────────────────────────────────────
$(TWEAK_NAME)_FILES  = Tweak.xm
# ImGui core
$(TWEAK_NAME)_FILES += imgui/imgui.cpp
$(TWEAK_NAME)_FILES += imgui/imgui_draw.cpp
$(TWEAK_NAME)_FILES += imgui/imgui_tables.cpp
$(TWEAK_NAME)_FILES += imgui/imgui_widgets.cpp
$(TWEAK_NAME)_FILES += imgui/imgui_impl_metal.mm
$(TWEAK_NAME)_FILES += imgui/imgui_impl_uikit.mm

# ── Architecture & SDK ───────────────────────────────────────────────────────
ARCHS                         = arm64
TARGET                        = iphone:clang:latest:14.0

# ── Compiler Flags ───────────────────────────────────────────────────────────
$(TWEAK_NAME)_CFLAGS          = -fobjc-arc -std=c++17 -O2 \
                                 -DIMGUI_IMPL_METAL_CPP \
                                 -Iimgui \
                                 -Wno-deprecated-declarations \
                                 -Wno-unused-variable

$(TWEAK_NAME)_CCFLAGS         = -fobjc-arc -std=c++17 -O2 \
                                 -DIMGUI_IMPL_METAL_CPP \
                                 -Iimgui \
                                 -Wno-deprecated-declarations \
                                 -Wno-unused-variable

$(TWEAK_NAME)_OBJCFLAGS       = -fobjc-arc -std=c++17 -O2 \
                                 -DIMGUI_IMPL_METAL_CPP \
                                 -Iimgui \
                                 -Wno-deprecated-declarations

# ── Linker Flags ─────────────────────────────────────────────────────────────
$(TWEAK_NAME)_FRAMEWORKS      = Metal MetalKit UIKit QuartzCore Foundation CoreGraphics

# Dobby is vendored as a static lib inside the Theos toolchain or
# a prebuilt placed in $THEOS/lib/. Adjust path if you host it elsewhere.
$(TWEAK_NAME)_LIBRARIES       = dobby
$(TWEAK_NAME)_LIBRARY_FLAGS   = -L$(THEOS)/lib

# ── Logos Flags ──────────────────────────────────────────────────────────────
$(TWEAK_NAME)_LOGOS_DEFAULT_GENERATOR = internal

include $(THEOS)/makefiles/tweak.mk

# ── Convenience ──────────────────────────────────────────────────────────────
after-install::
	install.exec "killall -9 Roblox || true"
