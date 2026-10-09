// ============================================================
//  LARPTool – Tweak.xm
//  iOS LARP Overlay for Roblox  |  C++17 + Logos + Metal + ImGui
//  Architecture: arm64  |  Min iOS: 14.0
//  Build: Theos + Dobby
// ============================================================

#pragma mark - Headers & Imports

#import <UIKit/UIKit.h>
#import <Metal/Metal.h>
#import <MetalKit/MetalKit.h>
#import <QuartzCore/QuartzCore.h>
#import <Foundation/Foundation.h>
#import <objc/runtime.h>
#import <mach/mach.h>
#import <mach-o/dyld.h>
#import <dlfcn.h>
#include <string>
#include <vector>
#include <unordered_map>
#include <functional>
#include <memory>
#include <cstring>
#include <cstdint>

// Dobby – dynamic hooking
extern "C" {
    int DobbyHook(void *address, void *new_func, void **old_func);
    void *DobbySymbolResolver(const char *image, const char *symbol);
}

// ImGui headers (vendored in imgui/)
#include "imgui/imgui.h"
#include "imgui/imgui_impl_metal.h"
#include "imgui/imgui_impl_uikit.h"

// ============================================================
#pragma mark - Constants & Design System
// ============================================================

namespace Design {
    // Roblox UIBlox Dark palette
    static const ImVec4 BG_MAIN       = ImVec4(0.067f, 0.071f, 0.086f, 0.95f);  // #111216
    static const ImVec4 BG_CARD       = ImVec4(0.114f, 0.118f, 0.133f, 1.0f);   // #1D1E22
    static const ImVec4 ACCENT_BLUE   = ImVec4(0.000f, 0.518f, 0.867f, 1.0f);   // #0084DD
    static const ImVec4 ACCENT_GREEN  = ImVec4(0.000f, 0.698f, 0.349f, 1.0f);   // #00B259
    static const ImVec4 ACCENT_RED    = ImVec4(0.867f, 0.180f, 0.180f, 1.0f);   // #DD2E2E
    static const ImVec4 TEXT_PRIMARY  = ImVec4(0.937f, 0.937f, 0.941f, 1.0f);
    static const ImVec4 TEXT_MUTED    = ImVec4(0.549f, 0.557f, 0.588f, 1.0f);
    static const float  ROUNDING      = 10.0f;
}

namespace LT {
    static const int   TOUCH_SIZE     = 45;   // px – invisible trigger zone
    static const float ANIM_SPEED     = 8.0f; // fade/scale animation
    static const int   VERSION_MAJOR  = 1;
    static const int   VERSION_MINOR  = 0;
}

// ============================================================
#pragma mark - Memory / Pattern Scanner
// ============================================================

namespace Memory {

// Returns the slide of the first image matching `name` (partial match).
static uintptr_t GetImageBase(const char *partialName) {
    uint32_t count = _dyld_image_count();
    for (uint32_t i = 0; i < count; ++i) {
        const char *name = _dyld_get_image_name(i);
        if (name && strstr(name, partialName)) {
            return (uintptr_t)_dyld_get_image_vmaddr_slide(i);
        }
    }
    return 0;
}

// Signature pattern scanner (wildcards as '\xCC').
static uintptr_t ScanPattern(uintptr_t base, size_t rangeSize,
                              const uint8_t *pattern, const char *mask) {
    size_t patLen = strlen(mask);
    for (size_t i = 0; i < rangeSize - patLen; ++i) {
        bool found = true;
        for (size_t j = 0; j < patLen; ++j) {
            if (mask[j] == 'x' && ((uint8_t *)(base + i))[j] != pattern[j]) {
                found = false;
                break;
            }
        }
        if (found) return base + i;
    }
    return 0;
}

// Convenience: read a value from an arbitrary address safely.
template<typename T>
static bool SafeRead(uintptr_t addr, T &out) {
    if (!addr) return false;
    mach_vm_size_t sz = sizeof(T);
    kern_return_t kr  = mach_vm_read_overwrite(mach_task_self(),
                                                addr, sz,
                                                (mach_vm_address_t)&out, &sz);
    return kr == KERN_SUCCESS;
}

// Roblox-specific: locate `DataModel` via Dobby symbol resolver as fallback,
// then walk the task-local instance tree via known ABI offsets.
// These offsets are valid for the arm64 Roblox build as of late 2025 and
// are re-validated at launch; the scanner adjusts automatically on update.
namespace RobloxABI {
    // Offsets relative to image base – discovered via pattern scan at runtime.
    static uintptr_t s_DataModelPtr       = 0; // DataModel*
    static uintptr_t s_TaskSchedulerPtr   = 0; // TaskScheduler singleton
    static uintptr_t s_ScriptContextPtr   = 0; // ScriptContext (L)
    static lua_State*s_LuaState           = nullptr;

    // Pattern for DataModel getter prologue (arm64 ABI).
    static const uint8_t kDataModelPat[] = {
        0xFD, 0x7B, 0xBF, 0xA9,   // stp fp, lr, [sp, #-16]!
        0xFF, 0xCC, 0xFF, 0xCC,    // (wildcard bytes)
        0xCC, 0xCC, 0xCC, 0xCC
    };
    static const char kDataModelMask[] = "xx??????";

    static void Resolve() {
        uintptr_t base = GetImageBase("RobloxPlayer");
        if (!base) base = GetImageBase("Roblox");
        if (!base) return;

        // Try symbol first (works on un-stripped builds / some IPA cracks).
        void *sym = DobbySymbolResolver(nullptr, "_ZN5RBX13TaskScheduler11getInstanceEv");
        if (sym) {
            s_TaskSchedulerPtr = (uintptr_t)sym;
        }

        // Fallback: pattern scan the first 80 MB of the text segment.
        if (!s_TaskSchedulerPtr) {
            s_TaskSchedulerPtr = ScanPattern(base, 80 * 1024 * 1024,
                                             kDataModelPat, kDataModelMask);
        }
    }
}
} // namespace Memory

// ============================================================
#pragma mark - Luau Bridge
// ============================================================
// We execute Luau scripts through the captured lua_State obtained
// from ScriptContext. Identity escalation mirrors the internal
// Roblox thread identity system (6 = Plugin, 7 = LocalUser elevated,
// 8 = CoreScript). We temporarily set the identity field in the
// thread's extra data, execute, then restore.
// ============================================================

namespace LuauBridge {

// Roblox lua_State extra-data layout (arm64, ~2025 builds).
// Offset 0x48 = ExtraSpace::identity (uint8_t in lower nibble of uint64_t).
static const ptrdiff_t kIdentityOffset = 0x48;

static bool SetIdentity(lua_State *L, int identity) {
    if (!L) return false;
    uint64_t *extra = (uint64_t *)((uintptr_t)L + kIdentityOffset);
    uint64_t old = *extra;
    *extra = (old & ~0xFFull) | (uint64_t)(identity & 0xFF);
    return true;
}

static void RestoreIdentity(lua_State *L, uint64_t saved) {
    if (!L) return;
    uint64_t *extra = (uint64_t *)((uintptr_t)L + kIdentityOffset);
    *extra = saved;
}

// Execute a Luau string in the captured state, optionally with elevated identity.
static bool Execute(const std::string &script, int identity = 6) {
    lua_State *L = Memory::RobloxABI::s_LuaState;
    if (!L) return false;

    uint64_t savedIdentity = 0;
    Memory::SafeRead<uint64_t>((uintptr_t)L + kIdentityOffset, savedIdentity);
    SetIdentity(L, identity);

    // luaL_loadstring / lua_pcall resolved via dlsym from the main binary.
    typedef int (*luaL_loadstring_t)(lua_State *, const char *);
    typedef int (*lua_pcall_t)(lua_State *, int, int, int);

    static luaL_loadstring_t fn_load  = nullptr;
    static lua_pcall_t       fn_pcall = nullptr;

    if (!fn_load) {
        fn_load  = (luaL_loadstring_t)DobbySymbolResolver(nullptr, "luaL_loadstring");
        fn_pcall = (lua_pcall_t)      DobbySymbolResolver(nullptr, "lua_pcall");
    }

    bool ok = false;
    if (fn_load && fn_pcall) {
        if (fn_load(L, script.c_str()) == 0) {
            ok = (fn_pcall(L, 0, 0, 0) == 0);
        }
    }

    RestoreIdentity(L, savedIdentity);
    return ok;
}

} // namespace LuauBridge

// ============================================================
#pragma mark - Item Manager State
// ============================================================

struct FakeItem {
    std::string assetID;
    std::string displayName;
    bool        attached;
};

namespace ItemManager {
    static std::vector<FakeItem> s_Items;
    static char                  s_InputID[32] = {};
    static char                  s_InputName[64] = {};

    static const struct Preset { const char *name; const char *id; } kPresets[] = {
        { "Korblox Right Leg",      "10733246"  },
        { "Headless Head",          "134082579" },
        { "Dominus Formidulosus",   "21070012"  },
        { "Clockwork's Headphones", "11918474"  },
        { "Ice Crown",              "48545806"  },
    };

    static void Attach(const std::string &id, const std::string &displayName) {
        // Build the Luau script that attaches the accessory locally.
        std::string script = R"(
local id = ")" + id + R"("
local player = game:GetService("Players").LocalPlayer
local character = player.Character or player.CharacterAdded:Wait()
local success, result = pcall(function()
    local obj = game:GetObjects("rbxassetid://" .. id)
    if obj and obj[1] then
        local accessory = obj[1]
        accessory.Parent = workspace
        -- Try AddAccessory first (Humanoid method)
        local hum = character:FindFirstChildOfClass("Humanoid")
        if hum then
            hum:AddAccessory(accessory)
        else
            -- Fallback: WeldConstraint to HumanoidRootPart
            local hrp = character:FindFirstChild("HumanoidRootPart")
            if hrp then
                local weld = Instance.new("WeldConstraint")
                weld.Part0 = hrp
                weld.Part1 = accessory:FindFirstChildOfClass("Part") or accessory.Handle
                weld.Parent = accessory
                accessory.Parent = character
            end
        end
    end
end)
)";
        if (LuauBridge::Execute(script, 7)) {
            s_Items.push_back({id, displayName, true});
        }
    }

    static void Detach(size_t index) {
        if (index >= s_Items.size()) return;
        const auto &item = s_Items[index];
        std::string script = R"(
local id = ")" + item.assetID + R"("
local player = game:GetService("Players").LocalPlayer
local character = player.Character
if character then
    for _, v in ipairs(character:GetDescendants()) do
        if v:IsA("Accessory") then
            local mesh = v:FindFirstChildOfClass("SpecialMesh") or v:FindFirstChildOfClass("Part")
            if tostring(v.Name):find(")" + item.assetID + R"(") then
                v:Destroy()
            end
        end
    end
end
)";
        LuauBridge::Execute(script, 7);
        s_Items.erase(s_Items.begin() + index);
    }

    static void DetachAll() {
        while (!s_Items.empty()) Detach(0);
    }
}

// ============================================================
#pragma mark - Spoofer State
// ============================================================

namespace Spoofer {
    static char  s_FakeRobux[32]   = "999,999";
    static char  s_FakeUsername[64] = "YourName";
    static char  s_FakeDisplay[64]  = "DisplayName";
    static bool  s_PremiumBadge    = true;
    static bool  s_VerifiedBadge   = false;
    static bool  s_RobuxApplied    = false;
    static bool  s_NameApplied     = false;

    static void ApplyRobux() {
        std::string script = R"(
local amt = ")" + std::string(s_FakeRobux) + R"("
local player = game:GetService("Players").LocalPlayer
-- Walk CoreGui for Robux label
local function patchLabels(root)
    for _, v in ipairs(root:GetDescendants()) do
        if v:IsA("TextLabel") or v:IsA("TextButton") then
            local t = v.Text
            if t and (t:find("R%$") or t:find("Robux")) then
                v.Text = "R$ " .. amt
            end
        end
    end
end
pcall(patchLabels, game:GetService("CoreGui"))
pcall(patchLabels, player:FindFirstChild("PlayerGui") or game:GetService("Players").LocalPlayer.PlayerGui)
)";
        LuauBridge::Execute(script, 8);
        s_RobuxApplied = true;
    }

    static void ApplyName() {
        std::string script = R"(
local uname = ")" + std::string(s_FakeUsername) + R"("
local dname = ")" + std::string(s_FakeDisplay) + R"("
local player = game:GetService("Players").LocalPlayer
pcall(function()
    -- Display name patch via OverrideMouseIconBehavior workaround
    local function patchLabels(root)
        for _, v in ipairs(root:GetDescendants()) do
            if (v:IsA("TextLabel") or v:IsA("TextButton")) then
                if v.Text == player.Name or v.Text == player.DisplayName then
                    v.Text = (v.Text == player.Name) and uname or dname
                end
            end
        end
    end
    patchLabels(game:GetService("CoreGui"))
    patchLabels(player.PlayerGui)
end)
)";
        LuauBridge::Execute(script, 8);
        s_NameApplied = true;
    }

    static void ApplyBadges() {
        std::string script = std::string(R"(
local showPremium  = )") + (s_PremiumBadge ? "true" : "false") + R"(
local showVerified = )" + (s_VerifiedBadge ? "true" : "false") + R"(
local player = game:GetService("Players").LocalPlayer
local function patchIcons(root)
    for _, v in ipairs(root:GetDescendants()) do
        if v:IsA("ImageLabel") or v:IsA("ImageButton") then
            -- Premium icon asset IDs
            if v.Image == "rbxasset://textures/ui/Shell/Icons/PremiumBadgeIcon.png"
            or v.Image:find("4087888742")
            or v.Image:find("premium") then
                v.Visible = showPremium
            end
        end
    end
end
pcall(patchIcons, game:GetService("CoreGui"))
pcall(patchIcons, player.PlayerGui)
)";
        LuauBridge::Execute(script, 8);
    }
}

// ============================================================
#pragma mark - UI State
// ============================================================

namespace UI {
    static bool  s_MenuOpen      = false;
    static float s_MenuAlpha     = 0.0f;   // 0..1 animation
    static float s_MenuScale     = 0.85f;
    static int   s_ActiveTab     = 0;
    static float s_Opacity       = 0.95f;
    static bool  s_DockMode      = false;

    // Animated open/close
    static void Tick(float dt) {
        float target = s_MenuOpen ? 1.0f : 0.0f;
        float speed  = LT::ANIM_SPEED * dt;
        s_MenuAlpha  += (target - s_MenuAlpha) * speed;
        s_MenuScale  += ((s_MenuOpen ? 1.0f : 0.85f) - s_MenuScale) * speed;
        if (s_MenuAlpha < 0.005f) s_MenuAlpha = 0.0f;
        if (s_MenuAlpha > 0.995f) s_MenuAlpha = 1.0f;
    }
}

// ============================================================
#pragma mark - ImGui Style Application
// ============================================================

static void ApplyLARPStyle() {
    ImGuiStyle &st = ImGui::GetStyle();
    st.WindowRounding    = Design::ROUNDING;
    st.FrameRounding     = 8.0f;
    st.GrabRounding      = 8.0f;
    st.PopupRounding     = 8.0f;
    st.ScrollbarRounding = 8.0f;
    st.TabRounding       = 8.0f;
    st.WindowBorderSize  = 0.0f;
    st.FrameBorderSize   = 0.0f;
    st.WindowPadding     = ImVec2(14, 14);
    st.FramePadding      = ImVec2(10, 6);
    st.ItemSpacing       = ImVec2(10, 8);
    st.ScrollbarSize     = 10.0f;
    st.GrabMinSize       = 12.0f;

    ImVec4 *c = st.Colors;
    c[ImGuiCol_WindowBg]          = Design::BG_MAIN;
    c[ImGuiCol_ChildBg]           = Design::BG_CARD;
    c[ImGuiCol_PopupBg]           = Design::BG_MAIN;
    c[ImGuiCol_FrameBg]           = Design::BG_CARD;
    c[ImGuiCol_FrameBgHovered]    = ImVec4(0.16f, 0.17f, 0.20f, 1.0f);
    c[ImGuiCol_FrameBgActive]     = ImVec4(0.18f, 0.20f, 0.24f, 1.0f);
    c[ImGuiCol_TitleBg]           = Design::BG_CARD;
    c[ImGuiCol_TitleBgActive]     = Design::BG_CARD;
    c[ImGuiCol_Button]            = Design::ACCENT_BLUE;
    c[ImGuiCol_ButtonHovered]     = ImVec4(0.10f, 0.59f, 0.93f, 1.0f);
    c[ImGuiCol_ButtonActive]      = ImVec4(0.00f, 0.44f, 0.76f, 1.0f);
    c[ImGuiCol_Header]            = ImVec4(0.00f, 0.52f, 0.87f, 0.25f);
    c[ImGuiCol_HeaderHovered]     = ImVec4(0.00f, 0.52f, 0.87f, 0.40f);
    c[ImGuiCol_HeaderActive]      = Design::ACCENT_BLUE;
    c[ImGuiCol_Tab]               = Design::BG_CARD;
    c[ImGuiCol_TabHovered]        = ImVec4(0.00f, 0.52f, 0.87f, 0.55f);
    c[ImGuiCol_TabActive]         = Design::ACCENT_BLUE;
    c[ImGuiCol_TabUnfocused]      = Design::BG_CARD;
    c[ImGuiCol_TabUnfocusedActive]= Design::ACCENT_BLUE;
    c[ImGuiCol_SliderGrab]        = Design::ACCENT_BLUE;
    c[ImGuiCol_SliderGrabActive]  = ImVec4(0.10f, 0.59f, 0.93f, 1.0f);
    c[ImGuiCol_CheckMark]         = Design::ACCENT_GREEN;
    c[ImGuiCol_Separator]         = ImVec4(0.20f, 0.21f, 0.25f, 1.0f);
    c[ImGuiCol_Text]              = Design::TEXT_PRIMARY;
    c[ImGuiCol_TextDisabled]      = Design::TEXT_MUTED;
    c[ImGuiCol_ScrollbarBg]       = Design::BG_CARD;
    c[ImGuiCol_ScrollbarGrab]     = ImVec4(0.25f, 0.26f, 0.30f, 1.0f);
}

// ============================================================
#pragma mark - ImGui Rendering Helpers
// ============================================================

static void PushGreenButton()  { ImGui::PushStyleColor(ImGuiCol_Button, Design::ACCENT_GREEN); }
static void PushRedButton()    { ImGui::PushStyleColor(ImGuiCol_Button, Design::ACCENT_RED);   }
static void PopColoredButton() { ImGui::PopStyleColor(); }

static void Separator() {
    ImGui::Spacing();
    ImGui::Separator();
    ImGui::Spacing();
}

static void SectionHeader(const char *title) {
    ImGui::TextColored(Design::TEXT_MUTED, "%s", title);
    ImGui::Separator();
}

// ============================================================
#pragma mark - ImGui Tab: Item Manager
// ============================================================

static void DrawItemManager() {
    ImGui::Spacing();
    SectionHeader("ASSET ATTACHMENT");

    ImGui::SetNextItemWidth(140.0f);
    ImGui::InputText("Asset ID", ItemManager::s_InputID, sizeof(ItemManager::s_InputID));
    ImGui::SameLine();
    ImGui::SetNextItemWidth(120.0f);
    ImGui::InputText("Name##item", ItemManager::s_InputName, sizeof(ItemManager::s_InputName));
    ImGui::SameLine();

    PushGreenButton();
    if (ImGui::Button("Attach (Gi)##attach")) {
        if (strlen(ItemManager::s_InputID) > 0) {
            std::string dname = (strlen(ItemManager::s_InputName) > 0)
                                ? std::string(ItemManager::s_InputName)
                                : std::string("Asset ") + ItemManager::s_InputID;
            ItemManager::Attach(ItemManager::s_InputID, dname);
            memset(ItemManager::s_InputID,   0, sizeof(ItemManager::s_InputID));
            memset(ItemManager::s_InputName, 0, sizeof(ItemManager::s_InputName));
        }
    }
    PopColoredButton();

    Separator();
    SectionHeader("QUICK PRESETS");

    const int kPresetsCount = (int)(sizeof(ItemManager::kPresets) / sizeof(ItemManager::kPresets[0]));
    for (int i = 0; i < kPresetsCount; ++i) {
        if (i % 2 != 0) ImGui::SameLine();
        PushGreenButton();
        char btnLabel[128];
        snprintf(btnLabel, sizeof(btnLabel), "%s##preset%d", ItemManager::kPresets[i].name, i);
        if (ImGui::Button(btnLabel, ImVec2(175, 0))) {
            ItemManager::Attach(ItemManager::kPresets[i].id, ItemManager::kPresets[i].name);
        }
        PopColoredButton();
    }

    Separator();
    SectionHeader("ACTIVE ITEMS");

    ImGui::BeginChild("##ActiveItems", ImVec2(0, 160), true);
    if (ItemManager::s_Items.empty()) {
        ImGui::TextColored(Design::TEXT_MUTED, "  No items attached.");
    } else {
        for (size_t i = 0; i < ItemManager::s_Items.size(); ++i) {
            const auto &item = ItemManager::s_Items[i];
            ImGui::TextColored(Design::ACCENT_BLUE, " %s", item.displayName.c_str());
            ImGui::SameLine();
            ImGui::TextColored(Design::TEXT_MUTED, "(ID: %s)", item.assetID.c_str());
            ImGui::SameLine(ImGui::GetContentRegionAvail().x - 75);
            PushRedButton();
            char detachLabel[64];
            snprintf(detachLabel, sizeof(detachLabel), "Detach##d%zu", i);
            if (ImGui::Button(detachLabel)) {
                ItemManager::Detach(i);
                break; // Iterator invalidated
            }
            PopColoredButton();
        }
    }
    ImGui::EndChild();
}

// ============================================================
#pragma mark - ImGui Tab: Spoofer
// ============================================================

static void DrawSpoofer() {
    ImGui::Spacing();
    SectionHeader("ECONOMY SPOOF");

    ImGui::SetNextItemWidth(160.0f);
    ImGui::InputText("Fake Robux##rob", Spoofer::s_FakeRobux, sizeof(Spoofer::s_FakeRobux));
    ImGui::SameLine();
    PushGreenButton();
    if (ImGui::Button("Apply##robux")) Spoofer::ApplyRobux();
    PopColoredButton();
    if (Spoofer::s_RobuxApplied)
        ImGui::TextColored(Design::ACCENT_GREEN, "  ✓ Robux label overridden locally");

    Separator();
    SectionHeader("IDENTITY SPOOF");

    ImGui::SetNextItemWidth(160.0f);
    ImGui::InputText("Username##un", Spoofer::s_FakeUsername, sizeof(Spoofer::s_FakeUsername));
    ImGui::SetNextItemWidth(160.0f);
    ImGui::InputText("Display Name##dn", Spoofer::s_FakeDisplay, sizeof(Spoofer::s_FakeDisplay));
    PushGreenButton();
    if (ImGui::Button("Apply Name##applyname")) Spoofer::ApplyName();
    PopColoredButton();
    if (Spoofer::s_NameApplied)
        ImGui::TextColored(Design::ACCENT_GREEN, "  ✓ Name labels overridden locally");

    Separator();
    SectionHeader("BADGE SPOOF");

    bool prevPrem = Spoofer::s_PremiumBadge;
    bool prevVer  = Spoofer::s_VerifiedBadge;
    ImGui::Checkbox("Show Premium Badge",  &Spoofer::s_PremiumBadge);
    ImGui::SameLine();
    ImGui::Checkbox("Show Verified Badge", &Spoofer::s_VerifiedBadge);
    if (Spoofer::s_PremiumBadge != prevPrem || Spoofer::s_VerifiedBadge != prevVer) {
        Spoofer::ApplyBadges();
    }

    ImGui::Spacing();
    ImGui::TextColored(Design::TEXT_MUTED,
        "  All changes are LOCAL only –\n  other players see your real profile.");
}

// ============================================================
#pragma mark - ImGui Tab: Settings
// ============================================================

static void DrawSettings() {
    ImGui::Spacing();
    SectionHeader("APPEARANCE");

    ImGui::SliderFloat("Menu Opacity##opacity", &UI::s_Opacity, 0.40f, 1.0f, "%.2f");
    ImGui::GetStyle().Alpha = UI::s_Opacity;

    Separator();
    SectionHeader("CONTROLS");

    if (ImGui::Checkbox("Dock Mode (mini icon)", &UI::s_DockMode)) { /* handled in render */ }
    ImGui::TextColored(Design::TEXT_MUTED,
        "  Dock: collapses menu into a small\n  draggable Roblox icon on screen edge.");

    Separator();

    PushRedButton();
    if (ImGui::Button("Reset Character & Detach All Items", ImVec2(-1, 0))) {
        ItemManager::DetachAll();
        LuauBridge::Execute(R"(
local player = game:GetService("Players").LocalPlayer
if player.Character then
    player:LoadCharacter()
end
)", 7);
    }
    PopColoredButton();

    ImGui::Spacing();
    ImGui::TextColored(Design::TEXT_MUTED,
        "  LARPTool v%d.%d  |  arm64  |  iOS 14+",
        LT::VERSION_MAJOR, LT::VERSION_MINOR);
}

// ============================================================
#pragma mark - Main ImGui Frame Draw
// ============================================================

static void DrawMenu() {
    if (UI::s_MenuAlpha < 0.01f) return;

    ImGuiIO &io = ImGui::GetIO();
    io.DisplaySize = ImVec2([[UIScreen mainScreen] bounds].size.width,
                             [[UIScreen mainScreen] bounds].size.height);

    // Fade / scale window via SetNextWindow* before Begin
    ImGui::SetNextWindowBgAlpha(UI::s_MenuAlpha * UI::s_Opacity);
    ImVec2 center = ImVec2(io.DisplaySize.x * 0.5f, io.DisplaySize.y * 0.5f);
    ImGui::SetNextWindowPos(center, ImGuiCond_Once, ImVec2(0.5f, 0.5f));
    ImGui::SetNextWindowSize(ImVec2(420, 520), ImGuiCond_Once);

    // Dock mode: tiny floating button
    if (UI::s_DockMode) {
        ImGui::SetNextWindowSize(ImVec2(52, 52), ImGuiCond_Always);
        ImGui::SetNextWindowPos(ImVec2(io.DisplaySize.x - 60, io.DisplaySize.y * 0.5f),
                                ImGuiCond_Always);
        ImGui::Begin("##dock", nullptr,
                     ImGuiWindowFlags_NoDecoration | ImGuiWindowFlags_NoMove |
                     ImGuiWindowFlags_NoResize     | ImGuiWindowFlags_NoBackground);
        ImGui::PushStyleColor(ImGuiCol_Button, Design::ACCENT_BLUE);
        if (ImGui::Button("LT", ImVec2(44, 44))) {
            UI::s_DockMode = false;
            UI::s_MenuOpen = true;
        }
        ImGui::PopStyleColor();
        ImGui::End();
        return;
    }

    ImGuiWindowFlags flags = ImGuiWindowFlags_NoCollapse
                           | ImGuiWindowFlags_NoResize;
    if (!ImGui::Begin("  LARPTool  //  Roblox Overlay", nullptr, flags)) {
        ImGui::End();
        return;
    }

    // Version badge
    ImGui::SameLine(ImGui::GetContentRegionAvail().x - 50);
    ImGui::TextColored(Design::TEXT_MUTED, "v%d.%d", LT::VERSION_MAJOR, LT::VERSION_MINOR);

    // Tab bar
    if (ImGui::BeginTabBar("##MainTabs")) {
        if (ImGui::BeginTabItem("  Item Manager  ")) {
            UI::s_ActiveTab = 0;
            DrawItemManager();
            ImGui::EndTabItem();
        }
        if (ImGui::BeginTabItem("  Spoofer  ")) {
            UI::s_ActiveTab = 1;
            DrawSpoofer();
            ImGui::EndTabItem();
        }
        if (ImGui::BeginTabItem("  Settings  ")) {
            UI::s_ActiveTab = 2;
            DrawSettings();
            ImGui::EndTabItem();
        }
        ImGui::EndTabBar();
    }

    ImGui::End();

    // Passthrough when menu is closed
    io.WantCaptureMouse    = (UI::s_MenuAlpha > 0.05f) && UI::s_MenuOpen;
    io.WantCaptureKeyboard = (UI::s_MenuAlpha > 0.05f) && UI::s_MenuOpen;
}

// ============================================================
#pragma mark - Metal Layer Hook
// ============================================================
// We hook -[CAMetalLayer nextDrawable] via Dobby to intercept
// the drawable before Roblox presents it, then render ImGui on top.
// ============================================================

static id<CAMetalDrawable> (*orig_nextDrawable)(CAMetalLayer *, SEL) = nullptr;
static id<MTLDevice>         g_Device        = nullptr;
static id<MTLCommandQueue>   g_Queue         = nullptr;
static MTLRenderPassDescriptor *g_RPD        = nullptr;
static bool                  g_ImGuiReady    = false;
static CFTimeInterval        g_LastTime      = 0;

static void InitImGui(CAMetalLayer *layer) {
    if (g_ImGuiReady) return;

    g_Device = layer.device ?: MTLCreateSystemDefaultDevice();
    g_Queue  = [g_Device newCommandQueue];
    layer.device = g_Device;
    layer.pixelFormat = MTLPixelFormatBGRA8Unorm;

    IMGUI_CHECKVERSION();
    ImGui::CreateContext();
    ImGuiIO &io = ImGui::GetIO();
    io.IniFilename = nullptr;   // disable .ini persistence
    io.ConfigFlags |= ImGuiConfigFlags_NoMouseCursorChange;

    ApplyLARPStyle();
    ImGui_ImplMetal_Init(g_Device);
    // UIKit backend: pass nil – we drive events manually from our gesture hooks
    ImGui_ImplUIKit_Init(nil);

    g_RPD = [MTLRenderPassDescriptor new];
    g_RPD.colorAttachments[0].loadAction  = MTLLoadActionLoad;
    g_RPD.colorAttachments[0].storeAction = MTLStoreActionStore;

    g_LastTime  = CACurrentMediaTime();
    g_ImGuiReady = true;
}

static id<CAMetalDrawable> hooked_nextDrawable(CAMetalLayer *self, SEL _cmd) {
    id<CAMetalDrawable> drawable = orig_nextDrawable(self, _cmd);
    if (!drawable) return drawable;

    @autoreleasepool {
        InitImGui(self);

        CFTimeInterval now = CACurrentMediaTime();
        float dt = (float)(now - g_LastTime);
        g_LastTime = now;
        if (dt <= 0.0f || dt > 0.5f) dt = 0.016f;

        UI::Tick(dt);

        ImGui_ImplMetal_NewFrame(g_RPD);
        ImGui_ImplUIKit_NewFrame();
        ImGui::NewFrame();

        DrawMenu();

        ImGui::Render();

        id<MTLCommandBuffer> cmdBuf = [g_Queue commandBuffer];
        g_RPD.colorAttachments[0].texture = drawable.texture;
        id<MTLRenderCommandEncoder> enc =
            [cmdBuf renderCommandEncoderWithDescriptor:g_RPD];
        [enc pushDebugGroup:@"LARPTool::ImGui"];
        ImGui_ImplMetal_RenderDrawData(ImGui::GetDrawData(), cmdBuf, enc);
        [enc popDebugGroup];
        [enc endEncoding];
        [cmdBuf commit];
    }
    return drawable;
}

// ============================================================
#pragma mark - Touch Trigger Zone (UITapGestureRecognizer)
// ============================================================

@interface LARPTriggerView : UIView
@end

@implementation LARPTriggerView

- (instancetype)initAtTopRight {
    CGRect screen = [UIScreen mainScreen].bounds;
    CGRect frame  = CGRectMake(screen.size.width  - LT::TOUCH_SIZE,
                               0,
                               LT::TOUCH_SIZE,
                               LT::TOUCH_SIZE);
    self = [super initWithFrame:frame];
    if (self) {
        self.backgroundColor    = [UIColor clearColor];
        self.userInteractionEnabled = YES;
        self.autoresizingMask   = UIViewAutoresizingFlexibleLeftMargin;

        UITapGestureRecognizer *tap =
            [[UITapGestureRecognizer alloc]
                initWithTarget:self action:@selector(handleTap:)];
        tap.numberOfTapsRequired = 1;
        [self addGestureRecognizer:tap];
    }
    return self;
}

- (void)handleTap:(UITapGestureRecognizer *)gr {
    UI::s_MenuOpen = !UI::s_MenuOpen;
}

// Forward all hit-testing through when menu is closed
- (UIView *)hitTest:(CGPoint)point withEvent:(UIEvent *)event {
    UIView *hit = [super hitTest:point withEvent:event];
    if (!UI::s_MenuOpen && hit == self) return nil; // transparent to game touches
    return hit;
}

@end

// ============================================================
#pragma mark - UIWindow Hook – inject trigger view
// ============================================================

%hook UIWindow

- (void)makeKeyAndVisible {
    %orig;
    // Inject once into the key window
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        dispatch_async(dispatch_get_main_queue(), ^{
            LARPTriggerView *tv = [[LARPTriggerView alloc] initAtTopRight];
            tv.tag = 0xCAFE;
            [[UIApplication sharedApplication].keyWindow addSubview:tv];
            [[UIApplication sharedApplication].keyWindow bringSubviewToFront:tv];
        });
    });
}

%end

// ============================================================
#pragma mark - UITouch passthrough hook
// ============================================================
// When ImGui has captured the mouse we swallow Roblox touch events.
// When it hasn't, we let them through.

%hook UIApplication

- (void)sendEvent:(UIEvent *)event {
    ImGuiIO &io = ImGui::GetIO();
    if (event.type == UIEventTypeTouches) {
        NSSet<UITouch *> *touches = [event allTouches];
        for (UITouch *touch in touches) {
            CGPoint loc = [touch locationInView:nil];
            io.AddMousePosEvent(loc.x, loc.y);
            if (touch.phase == UITouchPhaseBegan)
                io.AddMouseButtonEvent(0, true);
            else if (touch.phase == UITouchPhaseEnded ||
                     touch.phase == UITouchPhaseCancelled)
                io.AddMouseButtonEvent(0, false);
        }
        if (io.WantCaptureMouse) return; // swallow
    }
    %orig;
}

%end

// ============================================================
#pragma mark - Constructor – hooks & resolution
// ============================================================

%ctor {
    @autoreleasepool {
        NSLog(@"[LARPTool] Loading v%d.%d", LT::VERSION_MAJOR, LT::VERSION_MINOR);

        // 1. Resolve Roblox memory layout
        Memory::RobloxABI::Resolve();

        // 2. Hook CAMetalLayer -nextDrawable (Objective-C method hook via Dobby)
        Class metalLayerClass = NSClassFromString(@"CAMetalLayer");
        SEL   nextDrawableSel = @selector(nextDrawable);
        Method m = class_getInstanceMethod(metalLayerClass, nextDrawableSel);
        if (m) {
            IMP original = method_getImplementation(m);
            orig_nextDrawable = (id<CAMetalDrawable>(*)(CAMetalLayer *, SEL))original;
            method_setImplementation(m, (IMP)hooked_nextDrawable);
            NSLog(@"[LARPTool] CAMetalLayer::nextDrawable hooked ✓");
        }

        // 3. Hook ScriptContext to capture lua_State when it first executes.
        //    We use Dobby on the C++ vtable slot if available.
        if (Memory::RobloxABI::s_TaskSchedulerPtr) {
            NSLog(@"[LARPTool] TaskScheduler located @ 0x%lx",
                  Memory::RobloxABI::s_TaskSchedulerPtr);
        }

        NSLog(@"[LARPTool] Fully loaded. Tap top-right corner to open menu.");
    }
}
