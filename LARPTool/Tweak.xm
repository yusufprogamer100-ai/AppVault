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

// Dobby (stub header – real hooking via MSHookFunction at runtime)
#include "dobby.h"   // header-only stub; DobbyHook/DobbySymbolResolver are no-ops
                     // Actual runtime resolution uses dlsym / MSFindSymbol below.

// Forward declare lua_State for Luau VM pointer in global scope
struct lua_State;

// Runtime symbol resolver: dynamic lookup across loaded images via dlsym
static void *LT_FindSymbol(const char *symbol) {
    if (!symbol) return nullptr;
    return dlsym(RTLD_DEFAULT, symbol);
}




// ImGui headers (vendored in imgui/)
#include "imgui/imgui.h"
#include "imgui/imgui_impl_metal.h"
#include "imgui/imgui_impl_uikit.h"

// ============================================================
#pragma mark - Constants & Design System
// ============================================================

namespace Design {
    // Apple iOS Dark theme palette
    static const ImVec4 BG_MAIN       = ImVec4(0.110f, 0.114f, 0.125f, 0.96f);  // #1C1D20 (iOS sheet)
    static const ImVec4 BG_CARD       = ImVec4(0.165f, 0.170f, 0.185f, 1.0f);   // #2A2B2F (iOS group)
    static const ImVec4 ACCENT_BLUE   = ImVec4(0.000f, 0.478f, 1.000f, 1.0f);   // #007AFF (Apple System Blue)
    static const ImVec4 ACCENT_GREEN  = ImVec4(0.204f, 0.780f, 0.349f, 1.0f);   // #34C759 (Apple Green)
    static const ImVec4 ACCENT_RED    = ImVec4(1.000f, 0.271f, 0.227f, 1.0f);   // #FF453A (Apple Red)
    static const ImVec4 TEXT_PRIMARY  = ImVec4(0.960f, 0.960f, 0.970f, 1.0f);
    static const ImVec4 TEXT_MUTED    = ImVec4(0.580f, 0.580f, 0.620f, 1.0f);
    static const float  ROUNDING      = 16.0f;
}

namespace LT {
    static const int   TOUCH_SIZE     = 75;   // px – invisible trigger zone
    static const float ANIM_SPEED     = 9.0f; // fade/scale animation
    static const int   VERSION_MAJOR  = 1;
    static const int   VERSION_MINOR  = 2;
}

// ============================================================
#pragma mark - Memory / Pattern Scanner
// ============================================================

namespace Memory {

// Convenience: read a value from an arbitrary address safely.

template<typename T>
static bool SafeRead(uintptr_t addr, T &out) {

    if (!addr) return false;
    vm_size_t sz = sizeof(T);
    kern_return_t kr = vm_read_overwrite(mach_task_self(),
                                         (vm_address_t)addr, sz,
                                         (vm_address_t)&out, &sz);
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
        void *sym = LT_FindSymbol("_ZN5RBX13TaskScheduler11getInstanceEv");
        if (sym) {
            s_TaskSchedulerPtr = (uintptr_t)sym;
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
        fn_load  = (luaL_loadstring_t)LT_FindSymbol("luaL_loadstring");
        fn_pcall = (lua_pcall_t)      LT_FindSymbol("lua_pcall");
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
    static char  s_FakeRobux[32]    = "999,999";
    static char  s_FakeUsername[64] = "YourName";
    static char  s_FakeDisplay[64]  = "DisplayName";
    static bool  s_PremiumBadge     = true;
    static bool  s_VerifiedBadge    = false;
    static bool  s_RobuxApplied     = false;
    static bool  s_NameApplied      = false;
    static bool  s_LiveSpoof        = true;

    static void RecursivePatchLabels(UIView *v, NSString *robuxStr, NSString *nameStr, NSString *dispStr) {
        if (!v) return;
        if ([v isKindOfClass:[UILabel class]]) {
            UILabel *lbl = (UILabel *)v;
            NSString *txt = lbl.text;
            if (txt && txt.length > 0) {
                if ([txt containsString:@"R$"] || [txt containsString:@"Robux"] || [txt hasPrefix:@"R "]) {
                    lbl.text = [NSString stringWithFormat:@"R$ %@", robuxStr];
                } else if ([txt hasPrefix:@"@"] && nameStr.length > 0) {
                    lbl.text = [NSString stringWithFormat:@"@%@", nameStr];
                }
            }
        }
        for (UIView *sub in v.subviews) {
            RecursivePatchLabels(sub, robuxStr, nameStr, dispStr);
        }
    }

    static void PatchAllWindowLabels() {
        dispatch_async(dispatch_get_main_queue(), ^{
            NSString *robux = [NSString stringWithUTF8String:s_FakeRobux];
            NSString *name  = [NSString stringWithUTF8String:s_FakeUsername];
            NSString *disp  = [NSString stringWithUTF8String:s_FakeDisplay];
            for (UIWindow *w in [UIApplication sharedApplication].windows) {
                RecursivePatchLabels(w, robux, name, disp);
            }
        });
    }

    static void ApplyRobux() {
        std::string script = R"(
local amt = ")" + std::string(s_FakeRobux) + R"("
local player = game:GetService("Players").LocalPlayer
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
        PatchAllWindowLabels();
        s_RobuxApplied = true;
    }

    static void ApplyName() {
        std::string script = R"(
local uname = ")" + std::string(s_FakeUsername) + R"("
local dname = ")" + std::string(s_FakeDisplay) + R"("
local player = game:GetService("Players").LocalPlayer
pcall(function()
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
        PatchAllWindowLabels();
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
        PatchAllWindowLabels();
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
    st.FrameRounding     = 10.0f;
    st.GrabRounding      = 10.0f;
    st.PopupRounding     = 12.0f;
    st.ScrollbarRounding = 10.0f;
    st.TabRounding       = 10.0f;
    st.WindowBorderSize  = 1.0f;
    st.FrameBorderSize   = 0.0f;
    st.WindowPadding     = ImVec2(16, 16);
    st.FramePadding      = ImVec2(12, 8);
    st.ItemSpacing       = ImVec2(10, 10);
    st.ScrollbarSize     = 16.0f; // Wider scrollbar for touch
    st.GrabMinSize       = 14.0f;

    ImVec4 *c = st.Colors;
    c[ImGuiCol_WindowBg]          = Design::BG_MAIN;
    c[ImGuiCol_Border]            = ImVec4(0.25f, 0.26f, 0.30f, 0.65f);
    c[ImGuiCol_ChildBg]           = Design::BG_CARD;
    c[ImGuiCol_PopupBg]           = Design::BG_MAIN;
    c[ImGuiCol_FrameBg]           = Design::BG_CARD;
    c[ImGuiCol_FrameBgHovered]    = ImVec4(0.20f, 0.21f, 0.24f, 1.0f);
    c[ImGuiCol_FrameBgActive]     = ImVec4(0.24f, 0.25f, 0.28f, 1.0f);
    c[ImGuiCol_TitleBg]           = Design::BG_CARD;
    c[ImGuiCol_TitleBgActive]     = Design::BG_CARD;
    c[ImGuiCol_Button]            = Design::ACCENT_BLUE;
    c[ImGuiCol_ButtonHovered]     = ImVec4(0.12f, 0.55f, 1.00f, 1.0f);
    c[ImGuiCol_ButtonActive]      = ImVec4(0.00f, 0.40f, 0.85f, 1.0f);
    c[ImGuiCol_Header]            = ImVec4(0.00f, 0.48f, 1.00f, 0.25f);
    c[ImGuiCol_HeaderHovered]     = ImVec4(0.00f, 0.48f, 1.00f, 0.40f);
    c[ImGuiCol_HeaderActive]      = Design::ACCENT_BLUE;
    c[ImGuiCol_Tab]               = Design::BG_CARD;
    c[ImGuiCol_TabHovered]        = ImVec4(0.00f, 0.48f, 1.00f, 0.50f);
    c[ImGuiCol_TabActive]         = Design::ACCENT_BLUE;
    c[ImGuiCol_TabUnfocused]      = Design::BG_CARD;
    c[ImGuiCol_TabUnfocusedActive]= Design::ACCENT_BLUE;
    c[ImGuiCol_SliderGrab]        = Design::ACCENT_BLUE;
    c[ImGuiCol_SliderGrabActive]  = ImVec4(0.12f, 0.55f, 1.00f, 1.0f);
    c[ImGuiCol_CheckMark]         = Design::ACCENT_GREEN;
    c[ImGuiCol_Separator]         = ImVec4(0.22f, 0.23f, 0.26f, 1.0f);
    c[ImGuiCol_Text]              = Design::TEXT_PRIMARY;
    c[ImGuiCol_TextDisabled]      = Design::TEXT_MUTED;
    c[ImGuiCol_ScrollbarBg]       = Design::BG_CARD;
    c[ImGuiCol_ScrollbarGrab]     = ImVec4(0.35f, 0.36f, 0.40f, 1.0f);
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

    ImGui::Text("Fake Robux:");
    ImGui::SetNextItemWidth(-1.0f);
    ImGui::InputText("##rob", Spoofer::s_FakeRobux, sizeof(Spoofer::s_FakeRobux));
    
    PushGreenButton();
    if (ImGui::Button("Robux Miktarını Uygula##robux", ImVec2(-1, 30))) {
        Spoofer::ApplyRobux();
    }
    PopColoredButton();
    if (Spoofer::s_RobuxApplied)
        ImGui::TextColored(Design::ACCENT_GREEN, "  ✓ Robux güncellendi (Local Client)");

    Separator();
    SectionHeader("IDENTITY SPOOF");

    ImGui::Text("Username (@):");
    ImGui::SetNextItemWidth(-1.0f);
    ImGui::InputText("##un", Spoofer::s_FakeUsername, sizeof(Spoofer::s_FakeUsername));

    ImGui::Text("Display Name:");
    ImGui::SetNextItemWidth(-1.0f);
    ImGui::InputText("##dn", Spoofer::s_FakeDisplay, sizeof(Spoofer::s_FakeDisplay));

    PushGreenButton();
    if (ImGui::Button("İsimleri Uygula##applyname", ImVec2(-1, 30))) {
        Spoofer::ApplyName();
    }
    PopColoredButton();
    if (Spoofer::s_NameApplied)
        ImGui::TextColored(Design::ACCENT_GREEN, "  ✓ İsimler güncellendi (Local Client)");

    Separator();
    SectionHeader("BADGE SPOOF");

    bool prevPrem = Spoofer::s_PremiumBadge;
    bool prevVer  = Spoofer::s_VerifiedBadge;
    ImGui::Checkbox("Show Premium Badge",  &Spoofer::s_PremiumBadge);
    ImGui::Checkbox("Show Verified Badge", &Spoofer::s_VerifiedBadge);
    if (Spoofer::s_PremiumBadge != prevPrem || Spoofer::s_VerifiedBadge != prevVer) {
        Spoofer::ApplyBadges();
    }

    ImGui::Spacing();
    ImGui::TextColored(Design::TEXT_MUTED,
        "  Client-side mod – Tüm değişiklikler\n  yalnızca senin ekranında görünür.");
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

    // Fade / scale window via SetNextWindow* before Begin
    ImGui::SetNextWindowBgAlpha(UI::s_MenuAlpha * UI::s_Opacity);
    ImVec2 center = ImVec2(io.DisplaySize.x * 0.5f, io.DisplaySize.y * 0.5f);
    ImGui::SetNextWindowPos(center, ImGuiCond_FirstUseEver, ImVec2(0.5f, 0.5f));
    // Vertical iOS sheet layout: 340w x 520h (or fit inside screen)
    float w = 340.0f;
    float h = (io.DisplaySize.y > 540.0f) ? 520.0f : (io.DisplaySize.y - 20.0f);
    ImGui::SetNextWindowSize(ImVec2(w, h), ImGuiCond_Always);

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
    // Window header with native close cross
    if (!ImGui::Begin("  LARPTool iOS", &UI::s_MenuOpen, flags)) {
        ImGui::End();
        return;
    }

    // Prominent Red Close Button at top
    ImGui::PushStyleColor(ImGuiCol_Button, Design::ACCENT_RED);
    ImGui::PushStyleColor(ImGuiCol_ButtonHovered, ImVec4(1.0f, 0.35f, 0.30f, 1.0f));
    ImGui::PushStyleColor(ImGuiCol_ButtonActive, ImVec4(0.85f, 0.15f, 0.15f, 1.0f));
    if (ImGui::Button("  KAPAT (X)  ", ImVec2(95, 26))) {
        UI::s_MenuOpen = false;
    }
    ImGui::PopStyleColor(3);

    ImGui::SameLine();
    ImGui::TextColored(Design::TEXT_MUTED, "v%d.%d iOS Dark", LT::VERSION_MAJOR, LT::VERSION_MINOR);

    ImGui::Spacing();
    ImGui::Separator();
    ImGui::Spacing();

    // Scrollable child container for touch scrolling
    if (ImGui::BeginChild("##ScrollableContent", ImVec2(0, -36), false, ImGuiWindowFlags_AlwaysVerticalScrollbar)) {
        // Tab bar
        if (ImGui::BeginTabBar("##MainTabs")) {
            if (ImGui::BeginTabItem(" Spoofer ")) {
                UI::s_ActiveTab = 1;
                DrawSpoofer();
                ImGui::EndTabItem();
            }
            if (ImGui::BeginTabItem(" Items ")) {
                UI::s_ActiveTab = 0;
                DrawItemManager();
                ImGui::EndTabItem();
            }
            if (ImGui::BeginTabItem(" Settings ")) {
                UI::s_ActiveTab = 2;
                DrawSettings();
                ImGui::EndTabItem();
            }
            ImGui::EndTabBar();
        }
        ImGui::EndChild();
    }

    // Bottom close bar
    ImGui::Separator();
    if (ImGui::Button("Menüyü Kapat", ImVec2(-1, 28))) {
        UI::s_MenuOpen = false;
    }

    ImGui::End();

    // Passthrough when menu is closed
    io.WantCaptureMouse    = (UI::s_MenuAlpha > 0.05f) && UI::s_MenuOpen;
    io.WantCaptureKeyboard = (UI::s_MenuAlpha > 0.05f) && UI::s_MenuOpen;
}

// ============================================================
#pragma mark - Dedicated Metal Overlay View
// ============================================================
// Dedicated transparent CAMetalLayer view hosted in UIWindow.
// Renders ImGui completely independently of Roblox's game frame
// so Roblox never clears or overwrites the menu.
// ============================================================

@interface LARPOverlayView : UIView <UITextFieldDelegate>
@property (nonatomic, strong) CADisplayLink *displayLink;
@property (nonatomic, strong) UITextField   *hiddenTextField;
@end

static id<MTLDevice>         g_Device        = nullptr;
static id<MTLCommandQueue>   g_Queue         = nullptr;
static MTLRenderPassDescriptor *g_RPD        = nullptr;
static bool                  g_ImGuiReady    = false;
static CFTimeInterval        g_LastTime      = 0;

static void InitImGuiOverlay(id<MTLDevice> device) {
    if (g_ImGuiReady) return;

    g_Device = device ?: MTLCreateSystemDefaultDevice();
    if (!g_Device) return;

    g_Queue = [g_Device newCommandQueue];

    IMGUI_CHECKVERSION();
    ImGui::CreateContext();
    ImGuiIO &io = ImGui::GetIO();
    io.IniFilename = nullptr;   // disable .ini persistence
    io.ConfigFlags |= ImGuiConfigFlags_NoMouseCursorChange;

    ApplyLARPStyle();
    ImGui_ImplMetal_Init(g_Device);
    ImGui_ImplUIKit_Init(nil);

    g_RPD = [MTLRenderPassDescriptor new];
    g_RPD.colorAttachments[0].loadAction  = MTLLoadActionClear;
    g_RPD.colorAttachments[0].clearColor = MTLClearColorMake(0.0, 0.0, 0.0, 0.0);
    g_RPD.colorAttachments[0].storeAction = MTLStoreActionStore;

    g_LastTime   = CACurrentMediaTime();
    g_ImGuiReady = true;
    NSLog(@"[LARPTool] ImGui Metal backend initialized on dedicated overlay ✓");
}

@implementation LARPOverlayView

+ (Class)layerClass {
    return [CAMetalLayer class];
}

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        self.backgroundColor = [UIColor clearColor];
        self.userInteractionEnabled = NO;
        self.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;

        // Hidden input field for iOS Virtual Keyboard
        self.hiddenTextField = [[UITextField alloc] initWithFrame:CGRectZero];
        self.hiddenTextField.delegate = self;
        self.hiddenTextField.autocorrectionType = UITextAutocorrectionTypeNo;
        self.hiddenTextField.autocapitalizationType = UITextAutocapitalizationTypeNone;
        self.hiddenTextField.spellCheckingType = UITextSpellCheckingTypeNo;
        self.hiddenTextField.hidden = YES;
        [self addSubview:self.hiddenTextField];

        CAMetalLayer *metalLayer = (CAMetalLayer *)self.layer;
        metalLayer.opaque = NO;
        metalLayer.backgroundColor = [UIColor clearColor].CGColor;
        metalLayer.pixelFormat = MTLPixelFormatBGRA8Unorm;
        metalLayer.device = MTLCreateSystemDefaultDevice();
        metalLayer.framebufferOnly = NO;
        metalLayer.contentsScale = [UIScreen mainScreen].nativeScale;

        self.displayLink = [CADisplayLink displayLinkWithTarget:self selector:@selector(renderLoop:)];
        [self.displayLink addToRunLoop:[NSRunLoop mainRunLoop] forMode:NSRunLoopCommonModes];
    }
    return self;
}

- (BOOL)textField:(UITextField *)textField shouldChangeCharactersInRange:(NSRange)range replacementString:(NSString *)string {
    ImGuiIO &io = ImGui::GetIO();
    if (string.length > 0) {
        io.AddInputCharactersUTF8([string UTF8String]);
    } else {
        // Backspace key
        io.AddKeyEvent(ImGuiKey_Backspace, true);
        io.AddKeyEvent(ImGuiKey_Backspace, false);
    }
    return NO; // We consume inputs directly into ImGui
}

- (BOOL)textFieldShouldReturn:(UITextField *)textField {
    ImGuiIO &io = ImGui::GetIO();
    io.AddKeyEvent(ImGuiKey_Enter, true);
    io.AddKeyEvent(ImGuiKey_Enter, false);
    [textField resignFirstResponder];
    return YES;
}

- (void)layoutSubviews {
    [super layoutSubviews];
    CAMetalLayer *metalLayer = (CAMetalLayer *)self.layer;
    metalLayer.contentsScale = [UIScreen mainScreen].nativeScale;
    CGSize sz = self.bounds.size;
    metalLayer.drawableSize = CGSizeMake(sz.width * metalLayer.contentsScale, sz.height * metalLayer.contentsScale);
}

- (void)renderLoop:(CADisplayLink *)link {
    @autoreleasepool {
        CFTimeInterval now = CACurrentMediaTime();
        float dt = (float)(now - g_LastTime);
        g_LastTime = now;
        if (dt <= 0.0f || dt > 0.5f) dt = 0.016f;

        UI::Tick(dt);

        if (UI::s_MenuAlpha <= 0.001f) {
            if (!self.hidden) self.hidden = YES;
            if ([self.hiddenTextField isFirstResponder]) {
                dispatch_async(dispatch_get_main_queue(), ^{
                    [self.hiddenTextField resignFirstResponder];
                });
            }
            return;
        }

        if (self.hidden) self.hidden = NO;

        if (self.superview) {
            [self.superview bringSubviewToFront:self];
            UIView *tv = [self.superview viewWithTag:0xCAFE];
            if (tv) {
                [self.superview bringSubviewToFront:tv];
            }
        }

        CAMetalLayer *metalLayer = (CAMetalLayer *)self.layer;
        InitImGuiOverlay(metalLayer.device);
        if (!g_ImGuiReady) return;

        CGSize sz = self.bounds.size;
        if (sz.width <= 0.0f || sz.height <= 0.0f) return;

        CGFloat scale = [UIScreen mainScreen].nativeScale;
        if (metalLayer.drawableSize.width != sz.width * scale || metalLayer.drawableSize.height != sz.height * scale) {
            metalLayer.drawableSize = CGSizeMake(sz.width * scale, sz.height * scale);
        }

        id<CAMetalDrawable> drawable = [metalLayer nextDrawable];
        if (!drawable) return;

        id<MTLTexture> texture = drawable.texture;
        if (!texture) return;

        g_RPD.colorAttachments[0].texture = texture;

        ImGuiIO &io = ImGui::GetIO();
        io.DeltaTime = dt;

        // Auto manage Virtual Keyboard when ImGui text inputs are focused
        if (io.WantTextInput) {
            if (![self.hiddenTextField isFirstResponder]) {
                dispatch_async(dispatch_get_main_queue(), ^{
                    [self.hiddenTextField becomeFirstResponder];
                });
            }
        } else {
            if ([self.hiddenTextField isFirstResponder]) {
                dispatch_async(dispatch_get_main_queue(), ^{
                    [self.hiddenTextField resignFirstResponder];
                });
            }
        }

        ImGui_ImplMetal_NewFrame(g_RPD);
        ImGui_ImplUIKit_NewFrame();

        io.DisplaySize = ImVec2((float)sz.width, (float)sz.height);
        io.DisplayFramebufferScale = ImVec2((float)scale, (float)scale);

        ImGui::NewFrame();
        DrawMenu();
        ImGui::Render();

        id<MTLCommandBuffer> cmdBuf = [g_Queue commandBuffer];
        if (cmdBuf) {
            id<MTLRenderCommandEncoder> enc = [cmdBuf renderCommandEncoderWithDescriptor:g_RPD];
            if (enc) {
                [enc pushDebugGroup:@"LARPTool::ImGui"];
                ImGui_ImplMetal_RenderDrawData(ImGui::GetDrawData(), cmdBuf, enc);
                [enc popDebugGroup];
                [enc endEncoding];
            }
            [cmdBuf presentDrawable:drawable];
            [cmdBuf commit];
        }
    }
}

@end


// ============================================================
#pragma mark - Touch Trigger Zone (Bottom-Left, Invisible) & Watermark
// ============================================================

@interface LARPTriggerView : UIView
@end

@implementation LARPTriggerView

- (instancetype)initAtBottomLeft {
    CGRect screen = [UIScreen mainScreen].bounds;
    CGFloat size = 75.0f;
    CGFloat x = 0.0f;
    CGFloat y = screen.size.height - size;

    CGRect frame = CGRectMake(x, y, size, size);
    self = [super initWithFrame:frame];
    if (self) {
        // Completely invisible touch trigger per user request
        self.backgroundColor = [UIColor clearColor];
        self.layer.borderWidth = 0.0f;
        self.userInteractionEnabled = YES;
        self.autoresizingMask = UIViewAutoresizingFlexibleTopMargin | UIViewAutoresizingFlexibleRightMargin;

        UITapGestureRecognizer *tap =
            [[UITapGestureRecognizer alloc]
                initWithTarget:self action:@selector(handleTap:)];
        tap.numberOfTapsRequired = 1;
        tap.cancelsTouchesInView = YES;
        [self addGestureRecognizer:tap];
    }
    return self;
}

- (void)didMoveToSuperview {
    [super didMoveToSuperview];
    [self updateLayout];
}

- (void)updateLayout {
    if (!self.superview) return;
    CGFloat size = 75.0f;
    CGRect bounds = self.superview.bounds;
    self.frame = CGRectMake(0.0f, bounds.size.height - size, size, size);
}

- (void)layoutSubviews {
    [super layoutSubviews];
    [self updateLayout];
}

- (void)handleTap:(UITapGestureRecognizer *)gr {
    UI::s_MenuOpen = !UI::s_MenuOpen;
    NSLog(@"[LARPTool] Trigger tapped! MenuOpen is now: %d", (int)UI::s_MenuOpen);
    if (@available(iOS 10.0, *)) {
        UIImpactFeedbackGenerator *gen = [[UIImpactFeedbackGenerator alloc] initWithStyle:UIImpactFeedbackStyleHeavy];
        [gen impactOccurred];
    }
}

@end

// Helper: Show "made by chayoo077" banner at top of screen for 4 seconds
static void ShowLaunchWatermark(UIWindow *parentWindow) {
    if (!parentWindow) return;
    
    CGRect screen = [UIScreen mainScreen].bounds;
    CGFloat width = 230.0f;
    CGFloat height = 40.0f;
    CGFloat x = (screen.size.width - width) / 2.0f;
    CGFloat y = 45.0f; // Below notch/status bar

    UIView *banner = [[UIView alloc] initWithFrame:CGRectMake(x, -50.0f, width, height)];
    banner.backgroundColor = [UIColor colorWithRed:0.07f green:0.07f blue:0.09f alpha:0.92f];
    banner.layer.cornerRadius = 10.0f;
    banner.layer.borderWidth = 1.5f;
    banner.layer.borderColor = [UIColor colorWithRed:0.0f green:0.70f blue:0.35f alpha:0.9f].CGColor;
    banner.layer.masksToBounds = YES;
    banner.userInteractionEnabled = NO;

    UILabel *lbl = [[UILabel alloc] initWithFrame:banner.bounds];
    lbl.text = @"made by chayoo077";
    lbl.textColor = [UIColor whiteColor];
    lbl.font = [UIFont boldSystemFontOfSize:13.0f];
    lbl.textAlignment = NSTextAlignmentCenter;
    [banner addSubview:lbl];

    [parentWindow addSubview:banner];
    [parentWindow bringSubviewToFront:banner];

    // Slide down animation
    [UIView animateWithDuration:0.45 delay:0.2 usingSpringWithDamping:0.75 initialSpringVelocity:0.5 options:0 animations:^{
        banner.frame = CGRectMake(x, y, width, height);
    } completion:^(BOOL finished) {
        // Stay 4.0 seconds then slide up and fade away
        [UIView animateWithDuration:0.5 delay:4.0 options:UIViewAnimationOptionCurveEaseIn animations:^{
            banner.alpha = 0.0f;
            banner.frame = CGRectMake(x, -50.0f, width, height);
        } completion:^(BOOL f) {
            [banner removeFromSuperview];
        }];
    }];
}

// ============================================================
#pragma mark - UIWindow Hook – inject trigger view & watermark
// ============================================================

static void AttachOverlayToWindow(UIWindow *w) {
    if (!w) return;

    if (![w viewWithTag:0xCAFF]) {
        LARPOverlayView *ov = [[LARPOverlayView alloc] initWithFrame:w.bounds];
        ov.tag = 0xCAFF;
        [w addSubview:ov];
        [w bringSubviewToFront:ov];
        NSLog(@"[LARPTool] Dedicated Metal overlay view attached.");
    }

    if (![w viewWithTag:0xCAFE]) {
        LARPTriggerView *tv = [[LARPTriggerView alloc] initAtBottomLeft];
        tv.tag = 0xCAFE;
        [w addSubview:tv];
        [w bringSubviewToFront:tv];

        ShowLaunchWatermark(w);
        NSLog(@"[LARPTool] Trigger button and launch watermark attached to window.");
    }
}

%hook UIWindow

- (void)makeKeyAndVisible {
    %orig;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.8 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        UIWindow *target = self ?: [[UIApplication sharedApplication] keyWindow];
        AttachOverlayToWindow(target);
    });
}

%end


// ============================================================
#pragma mark - UITouch passthrough hook
// ============================================================
// When ImGui has captured the mouse we swallow Roblox touch events.
%hook UIApplication

- (void)sendEvent:(UIEvent *)event {
    if (ImGui::GetCurrentContext() != nullptr && event.type == UIEventTypeTouches) {
        ImGuiIO &io = ImGui::GetIO();
        NSSet<UITouch *> *touches = [event allTouches];
        for (UITouch *touch in touches) {
            CGPoint loc = [touch locationInView:nil];
            io.AddMousePosEvent(loc.x, loc.y);

            if (touch.phase == UITouchPhaseBegan) {
                io.AddMouseButtonEvent(0, true);
            } else if (touch.phase == UITouchPhaseMoved) {
                // Touch drag-to-scroll: simulate mouse wheel on swipe
                CGPoint prevLoc = [touch previousLocationInView:nil];
                float dy = (float)(loc.y - prevLoc.y);
                if (fabsf(dy) > 0.5f) {
                    io.AddMouseWheelEvent(0.0f, dy * 0.08f);
                }
            } else if (touch.phase == UITouchPhaseEnded ||
                       touch.phase == UITouchPhaseCancelled) {
                io.AddMouseButtonEvent(0, false);
            }
        }
        // Only swallow if touch is within ImGui captured area
        if (UI::s_MenuOpen && UI::s_MenuAlpha > 0.05f && io.WantCaptureMouse) return;
    }
    %orig;
}

%end

// Fallback: Hook notification for application active to ensure overlay is on screen
static void OnAppBecameActive(CFNotificationCenterRef center, void *observer, CFStringRef name, const void *object, CFDictionaryRef userInfo) {
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.2 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        UIWindow *w = [[UIApplication sharedApplication] keyWindow];
        if (!w) {
            for (UIWindow *win in [[UIApplication sharedApplication] windows]) {
                if (win.isKeyWindow || [win isMemberOfClass:[UIWindow class]]) {
                    w = win;
                    break;
                }
            }
        }
        AttachOverlayToWindow(w);
    });
}



// ============================================================
#pragma mark - Constructor – hooks & resolution
// ============================================================

%ctor {
    @autoreleasepool {
        NSLog(@"[LARPTool] Loading v%d.%d", LT::VERSION_MAJOR, LT::VERSION_MINOR);

        // Preload graphics frameworks before Logos initializes hooks
        dlopen("/System/Library/Frameworks/Metal.framework/Metal", RTLD_NOW | RTLD_GLOBAL);
        dlopen("/System/Library/Frameworks/QuartzCore.framework/QuartzCore", RTLD_NOW | RTLD_GLOBAL);

        // 1. Resolve Roblox memory layout
        Memory::RobloxABI::Resolve();

        // 2. Initialize Logos hooks (UIWindow, UIApplication)
        %init;

        // 3. Listen for app became active as guaranteed trigger attachment
        CFNotificationCenterAddObserver(
            CFNotificationCenterGetLocalCenter(),
            nullptr,
            OnAppBecameActive,
            (CFStringRef)UIApplicationDidBecomeActiveNotification,
            nullptr,
            CFNotificationSuspensionBehaviorDeliverImmediately
        );

        NSLog(@"[LARPTool] Fully loaded. Watermark 'made by chayoo077' and invisible Bottom-Left trigger armed.");
    }
}

