# Embedder Layer-Shell 改造笔记（Phase 0 第 5/6 项）

> 目标：给 fork 的 `flutter-embedded-linux` 加 `wlr-layer-shell` 支持，让 Flutter 应用能创建
> shelf/overlay layer surface。本文沉淀全部调研结论，避免重复思考。
> 状态：**调研完成，代码未写**。两个已确认的阻塞见 §9。

## 0. 相关路径

| 路径 | 说明 |
|---|---|
| `MaterDE/embedder/` | sony/flutter-embedded-linux fork（基线 `1653fa6`，已并入 materde 主仓库） |
| `MaterDE/protocol/wlr-layer-shell-unstable-v1.xml` | 本地协议 XML（19326 字节，v5） |
| `MaterDE/protocol/xdg-shell.xml` | 本地 xdg-shell XML |
| ~~`MaterDE/poc/layer-shell-rs/`~~ | Rust PoC，验收通过后已删除（2026-09-24）；结论沉淀在本文与 docs/08 Go/No-Go 证据摘要 |
| `/tmp/opencode/ls.h` | 已用 wayland-scanner 生成的 layer-shell client header（验证用） |

## 1. 结论：上游完全没有 layer-shell

```
grep -rn "layer_shell|zwlr|wlr-layer" embedder-upstream/  → 无匹配
```

Wayland 实现在 `window/elinux_window_wayland.cc`（1931 行），只走 xdg-shell 普通窗口。
docs/08 风险 #1（HIGH, 30%）确认成立：必须自己写 C++ 协议代码。

## 2. 构建体系（已验证全部依赖可用）

- **CMake 强制 clang**（`CMakeLists.txt` 顶部 set CMAKE_CXX_COMPILER clang），本机 clang 22.1.8 ✅
- C++17；`cmake_minimum_required(VERSION 3.10)`
- 构建命令：
  ```bash
  cd embedder-upstream
  cmake -G Ninja -DUSER_PROJECT_PATH=examples/flutter-wayland-client -B build
  ninja -C build
  ```
- 协议生成在 `cmake/build.cmake` 的 wayland 分支（约 line 40-82）：
  `pkg_get_variable(WAYLAND_PROTOCOLS_DATADIR wayland-protocols pkgdatadir)` →
  `generate_wayland_client_protocol(PROTOCOL_FILE CODE_FILE HEADER_FILE)`（函数在 `cmake/generate_wayland_protocols.cmake`，内部调 `wayland-scanner client-header` / `private-code`）
  生成到 `${CMAKE_CURRENT_SOURCE_DIR}/src/third_party/wayland/protocols/`，
  生成的 .c 加入 `DISPLAY_BACKEND_SRC`。
- 现有生成 5 个协议：xdg-shell、text-input-v1、text-input-v3、presentation-time、xdg-decoration。
- 依赖检查 `cmake/package.cmake`：egl ✅ xkbcommon ✅ wayland-client/cursor/egl ✅
  **`wayland-protocols` ❌ 未安装**（见 §9 阻塞 2），glesv2 ✅
- 链接 `build/libflutter_engine.so`（`cmake/build.cmake:272`）——**该文件不存在**，
  完整链接需要 flutter-elinux 工具链下载引擎产物。见 §10。

## 3. 关键源码坐标（改造点）

### 3.1 公共 API：`src/flutter/shell/platform/linux_embedded/public/flutter_elinux.h`
- `enum FlutterDesktopViewMode { kNormalscreen=0, kFullscreen=1 }` (line ~60)
  → 加 `kLayerShell = 2`
- `FlutterDesktopViewProperties` 结构（width/height/view_rotation/view_mode/title/app_id/
  use_mouse_cursor/use_onscreen_keyboard/use_window_decoration/text_scale_factor/
  enable_high_contrast/force_scale_factor/scale_factor/enable_vsync）
  → 末尾追加 layer-shell 字段（见 §5）
- 已 `#include <stdint.h>`，可直接用 uint32_t/int32_t
- 导出函数 `FlutterDesktopViewControllerCreate(view_properties, engine)` (line ~141)

### 3.2 C++ wrapper：`src/client_wrapper/`
- `include/flutter/flutter_view_controller.h`
  - `enum ViewMode { kNormal=0, kFullscreen=1 }` (line 29) → 加 `kLayerShell=2`
  - `typedef struct {...} ViewProperties;` (line ~47) → 加字段
- `flutter_view_controller.cc:17` 构造 `FlutterDesktopViewProperties c_view_properties = {};`
  逐字段拷贝（line 18-47），`view_mode` 三元转换在 line 28-31 → 改成 switch/映射
  **所有构造点用 `= {}` 零初始化，追加字段安全**

### 3.3 窗口实现：`window/elinux_window_wayland.{h,cc}`
头文件已有 extern "C" 包含 5 个生成协议头（h line 23-29）→ 追加 layer-shell 头。

`elinux_window_wayland.h` 需加：
```cpp
static const zwlr_layer_surface_v1_listener kZwlrLayerSurfaceV1Listener;
zwlr_layer_shell_v1* zwlr_layer_shell_v1_ = nullptr;
zwlr_layer_surface_v1* zwlr_layer_surface_v1_ = nullptr;
bool layer_surface_configured_ = false;
```
（现有成员初始化风格：构造函数 init list 里显式 `=nullptr`，如 xdg_toplevel_(nullptr)）

`elinux_window_wayland.cc` 四处改动：
1. **registry 绑定** — `WlRegistryHandler()` (line 1620 起)，照 `xdg_wm_base` 分支抄：
   ```cpp
   if (!strcmp(interface, zwlr_layer_shell_v1_interface.name)) {
     constexpr uint32_t kMaxVersion = 5;
     zwlr_layer_shell_v1_ = static_cast<decltype(zwlr_layer_shell_v1_)>(
         wl_registry_bind(wl_registry, name, &zwlr_layer_shell_v1_interface,
                          std::min(kMaxVersion, version)));
     return;
   }
   ```
2. **listener 定义** — 照 `kXdgSurfaceListener` 模式（line 69-113），见 §6
3. **`CreateRenderSurface()`** (line 1364) — 分支点，见 §7
4. **清理** — `DestroyRenderSurface()`（xdg_surface_ 销毁处，line ~1290）+ 析构函数
   （line ~1180 起，x

, zxdg_decoration 销毁处）→ 销毁 layer surface / layer_shell

### 3.4 其它 view_mode 判断点（需确认不误伤）
- `elinux_window_wayland.cc:683` — wl_output.mode 回调里 `if (view_mode == kFullscreen)`
  → kLayerShell 不受影响，但**要跳过"clip 到 display 尺寸"逻辑**（layer surface 尺寸由 compositor 决定）
- `elinux_window_wayland.cc:1384,1438` — CreateRenderSurface 内两处 kFullscreen
- `elinux_window_drm.h:195` — DRM 后端强制 fullscreen（无关，我们只做 WAYLAND）
- `elinux_window_x11.cc:136` — X11（无关）

### 3.5 尺寸回传链（layer surface configure 后要走通）
```
configure 事件 → 更新 view_properties_.width/height + request_redraw_=true
→ DispatchEvent() (line 1305) 检测 request_redraw_
→ binding_handler_delegate_->OnWindowSizeChanged(w*scale, h*scale - decoration_h)  // line 1318
→ FlutterELinuxView::OnWindowSizeChanged (flutter_elinux_view.cc:96)
   → GetRenderSurfaceTarget()->OnScreenSurfaceResize(w_px, h_px)
      → SurfaceBase::OnScreenSurfaceResize (surface_base.cc:32)
         → onscreen_surface_->SurfaceResize + native_window_->Resize(wl_egl_window_resize)
   → SendWindowMetrics(w, h, dpi_scale)  // 通知 Flutter 引擎
```
即：**configure 里只需更新 view_properties_ + request_redraw_，resize 由现有链路自动完成**。

## 4. 生成的 layer-shell C API（已用 wayland-scanner 1.26.0 实测）

```c
// enum 数值（实测）
ZWLR_LAYER_SHELL_V1_LAYER_BACKGROUND = 0
ZWLR_LAYER_SHELL_V1_LAYER_BOTTOM     = 1
ZWLR_LAYER_SHELL_V1_LAYER_TOP        = 2
ZWLR_LAYER_SHELL_V1_LAYER_OVERLAY    = 3
ZWLR_LAYER_SURFACE_V1_ANCHOR_TOP     = 1
ZWLR_LAYER_SURFACE_V1_ANCHOR_BOTTOM  = 2
ZWLR_LAYER_SURFACE_V1_ANCHOR_LEFT    = 4
ZWLR_LAYER_SURFACE_V1_ANCHOR_RIGHT   = 8
ZWLR_LAYER_SURFACE_V1_KEYBOARD_INTERACTIVITY_NONE      = 0
ZWLR_LAYER_SURFACE_V1_KEYBOARD_INTERACTIVITY_EXCLUSIVE = 1
ZWLR_LAYER_SURFACE_V1_KEYBOARD_INTERACTIVITY_ON_DEMAND = 2  // @since 4

// 关键函数（注意：全是裸 uint32_t 参数，不是 enum 类型）
zwlr_layer_shell_v1_get_layer_surface(shell, surface, output_or_NULL,
                                      uint32_t layer, const char *ns)  // ← namespace 是 C++ 关键字！
zwlr_layer_shell_v1_destroy(shell)            // SINCE_VERSION 3
zwlr_layer_surface_v1_set_size(ls, uint32_t w, uint32_t h)
zwlr_layer_surface_v1_set_anchor(ls, uint32_t anchor)              // bitmask
zwlr_layer_surface_v1_set_exclusive_zone(ls, int32_t zone)
zwlr_layer_surface_v1_set_keyboard_interactivity(ls, uint32_t k)
zwlr_layer_surface_v1_ack_configure(ls, uint32_t serial)
zwlr_layer_surface_v1_destroy(ls)             // SINCE_VERSION 1
```
listener：`zwlr_layer_surface_v1_listener { configure(serial,w,h); closed(); }`

## 5. 计划的公共 API 扩展（flutter_elinux.h）

```c
enum FlutterDesktopViewMode {
  kNormalscreen = 0,
  kFullscreen   = 1,
  kLayerShell   = 2,   // 新增
};

typedef struct {
  FlutterDesktopLayerShellLayer layer;   // 0..3，对应 enum 值
  uint32_t anchor;                       // bitmask
  int32_t  exclusive_zone;
  const char* layer_namespace;           // 避开 C++ 关键字
  uint32_t keyboard_interactivity;
} FlutterDesktopLayerShellProperties;
// FlutterDesktopViewProperties 末尾追加:
//   FlutterDesktopLayerShellProperties layer_shell;
```
C++ wrapper `ViewProperties` 同步加同名字段（`std::optional<std::string>` 存 namespace）。

## 6. configure listener 设计（照 kXdgSurfaceListener 模式）

```cpp
const zwlr_layer_surface_v1_listener ELinuxWindowWayland::kZwlrLayerSurfaceV1Listener = {
  .configure = [](void* data, zwlr_layer_surface_v1* ls, uint32_t serial,
                  uint32_t width, uint32_t height) {
    auto self = reinterpret_cast<ELinuxWindowWayland*>(data);
    zwlr_layer_surface_v1_ack_configure(ls, serial);   // ← 必须先 ack！（C 版 PoC 漏了）
    // width/height 是 compositor 裁定的逻辑尺寸；0 表示沿用请求值
    if (width > 0 && height > 0 &&
        (self->view_properties_.width != (int)width ||
         self->view_properties_.height != (int)height)) {
      self->view_properties_.width = width;
      self->view_properties_.height = height;
      self->request_redraw_ = true;   // 触发 §3.5 的 resize 链路
    }
    self->layer_surface_configured_ = true;
    if (self->wait_for_configure_) self->wait_for_configure_ = false;
  },
  .closed = [](void* data, zwlr_layer_surface_v1* ls) {
    auto self = reinterpret_cast<ELinuxWindowWayland*>(data);
    self->running_ = false;
  },
};
```

## 7. CreateRenderSurface 分支设计（line 1364）

现有流程（xdg 路径）：
```
校验 display/wl_compositor/xdg_wm_base
→ (kFullscreen 时用 display 尺寸覆盖)
→ 建 wl_cursor_surface（如需）
→ rotation 交换 w/h
→ native_window_ = NativeWindowWayland(compositor, w, h, vsync)   // 内部 wl_compositor_create_surface + wl_egl_window_create
→ wl_surface_add_listener
→ xdg_wm_base_get_xdg_surface + get_toplevel + add_listener + set_title/app_id
→ wl_surface_set_buffer_scale(scale)
→ wl_surface_frame + presentation feedback
→ (kFullscreen: set_fullscreen)
→ wait_for_configure_=true; wl_surface_commit()
→ render_surface_ = SurfaceGl(ContextEgl(EnvironmentEgl))
→ (decoration)
→ while(wait_for_configure_) wl_display_dispatch()   // 阻塞等 configure
```

layer-shell 分支改 3 处：
1. 早退校验：`if (!xdg_wm_base_)` → layer 模式改为 `if (!zwlr_layer_shell_v1_)`
2. `xdg_get_surface/get_toplevel` 块 → 换成：
   ```cpp
   zwlr_layer_surface_v1_ = zwlr_layer_shell_v1_get_layer_surface(
       zwlr_layer_shell_v1_, native_window_->Surface(), /*output=*/nullptr,
       ls_props.layer, ls_props.layer_namespace);
   zwlr_layer_surface_v1_add_listener(zwlr_layer_surface_v1_,
                                      &kZwlrLayerSurfaceV1Listener, this);
   zwlr_layer_surface_v1_set_size(ls, view_properties_.width, view_properties_.height);
   zwlr_layer_surface_v1_set_anchor(ls, ls_props.anchor);
   zwlr_layer_surface_v1_set_exclusive_zone(ls, ls_props.exclusive_zone);
   zwlr_layer_surface_v1_set_keyboard_interactivity(ls, ls_props.keyboard_interactivity);
   ```
   **注意 shelf 规格（docs/03 §5, docs/04 §1）**：
   `set_size(0, 48)` 宽 0=由 compositor 按 anchor 决定；anchor=Bottom|Left|Right(2|4|8=14)；
   `exclusive_zone=48`；`keyboard_interactivity=None(0)`；layer=Bottom(1)
3. 跳过：decoration 创建、kFullscreen 的 set_fullscreen、"clip 到 display 尺寸"
4. `wait_for_configure_` 阻塞循环保留（layer surface 同样需要等首次 configure）

**尺寸坑**：`set_size(0,48)` 时 `native_window_` 初值 w 可能是 0/默认 1280。
configure 回来真实宽度（如 1646）后由 §3.5 链路 resize `wl_egl_window`。需确认初值不为 0
（`wl_egl_window_create(surface, 0, 48)` 可能失败）→ 分支里若 width<=0 先用
`display_max_width_`（wl_output.mode 已在构造 roundtrip 里拿到）兜底。

## 8. 示例程序 CLI（`examples/flutter-wayland-client/`）

- `flutter_embedder_options.h`：`AddWithoutValue/AddInt/AddDouble/AddString` 注册选项，
  `Parse()` 里 `Exist(name)` / `GetValue<T>(name)`，getter 转发。
  WAYLAND 分支在 `#else // FLUTTER_TARGET_BACKEND_WAYLAND`（line ~120-130）。
  → 加 `--layer-shell`、`--layer`、`--anchor`、`--exclusive-zone`、`--namespace`、`--keyboard`
- `main.cc:29-43` 把 options 填进 `view_properties` → 追加 layer 字段
- `cmake/user_build.cmake`：TARGET=flutter-client，已含三个源文件

## 9. 两个阻塞（**均已解除 ✅**，以下保留原始分析）

- **阻塞 A 解法 = A1（已实现）**：`cmake/generate_wayland_protocols.cmake` 加
  `PATCH_NS_KEYWORD` 开关，wayland-scanner 之后跑两条 sed
  （`-e "s/\*namespace)/\*ns)/" -e "s/, namespace)/, ns)/"`）。
  ⚠️ CMake 里**不能用 `;` 分隔 sed 表达式**（`set()` 的列表会被 `;` 拆开），
  必须写成两个 `-e`。已实测：生成头第 225 行 `const char *ns`、第 230 行 `, ns);`。
- **阻塞 B 解法**：用户已执行 `sudo pacman -S wayland-protocols`，
  `pkg-config --exists wayland-protocols` → OK，`/usr/share/wayland-protocols`，
  版本 1.49。

### 阻塞 A（原）：`namespace` 是 C++ 关键字 → 生成的头文件编译失败（已实测复现）
```
error: invalid parameter name: 'namespace' is a keyword
  zwlr_layer_shell_v1_get_layer_surface(..., const char *namespace)
```
**解决方案（选一）**：
- **A1（推荐）**：CMake 生成后加 sed 命令把 `namespace` → `ns`：
  ```cmake
  add_custom_command(OUTPUT ${hdr}
    COMMAND wayland-scanner client-header ${xml} ${hdr}
    COMMAND sed -i "s/\\*namespace)/\\*ns)/g; s/, namespace)/, ns)/g" ${hdr}
    DEPENDS ${xml} VERBATIM)
  ```
  需改 `cmake/generate_wayland_protocols.cmake` 或为 layer-shell 单独写一条。
- **A2**：手写一个 `layer_shell_shim.h`，只声明需要的函数（避开生成头）→ 维护成本高。
- **A3**：把 layer-shell 调用放进独立 `.c` 文件（C 允许 namespace 作标识符），
  C++ 侧只 include 自己的 shim 头。

### 阻塞 B：系统未安装 `wayland-protocols`
```
pacman -Qi wayland-protocols → 未找到
pkg-config --exists wayland-protocols → MISSING
```
`cmake/package.cmake:36` 是 `REQUIRED`，不装则 **configure 直接失败**。
xdg-shell.xml / text-input / presentation-time / xdg-decoration 全来自它。
**需 sudo**：`sudo pacman -S wayland-protocols`（本地 `protocol/xdg-shell.xml` 可备用，但另外 4 个没有）
→ **用户已确认自己在终端执行**，我继续写代码，稍后验证 pkg-config。

## 9bis. Context7 查询结论（`/sony/flutter-embedded-linux` + `/sony/flutter-elinux`）

**能查到什么 / 查不到什么**：
- ctx7 有这两个库（185 / 180 snippets），但索引内容 = **README + wiki**，**没有源码里的
  struct 定义**。`FlutterDesktopViewProperties` / `FlutterDesktopViewMode` 字段查询
  直接 "No documentation matched"。
- ⇒ 结论：**构建/运行策略先查 ctx7，struct 字段级细节才翻源码**。以后先 ctx7。

**ctx7 直接解掉的两个阻塞**：

1. **`libflutter_engine.so` 怎么来**（原 §10 障碍）
   - 必须放在 **CMake build 目录**（`build/`）里。
   - 官方下载：`curl -O https://storage.googleapis.com/flutter_infra/flutter/FLUTTER_ENGINE/linux-x64/linux-x64-embedder`
     （`FLUTTER_ENGINE` 换成目标 engine SHA）
   - 或从 engine 源码构建后 `cp ./out/<target>/libflutter_engine.so <cmake_build_dir>`

2. **embedder `.so` 是预编译的**（新认知，影响整个 fork 策略）
   - flutter-elinux 构建 app 时自动下载 artifact 到
     `<flutter-elinux_install>/flutter/bin/cache/artifacts/engine/`，
     其中含 `libflutter_engine.so` **和 `libflutter_elinux_wayland.so`**。
   - 即：**正常流程里 embedder 根本不重新编译**。fork 加 layer-shell ⇒
     要么自己 `ninja` 出 `.so` 覆盖 artifact，要么走本地 artifact 目录。
   - 本地 artifact 覆盖开关（wiki: Use-local-elinux-artifacts）：
     ```
     export ELINUX_ENGINE_BASE_LOCAL_DIRECTORY=<已下载 artifacts 的路径>
     export ELINUX_ENGINE_BASE_URL=<自建 artifact server>   # 默认 https://github.com/sony/flutter-embedded-linux/releases
     ```
   - glibc 约束：`libflutter_engine.so` 用 Chromium clang + glibc 2.29 构建；
     `libflutter_elinux_*.so` 用 Ubuntu 18.04 clang + **glibc 2.27** 构建。

**其它 ctx7 拿到的运行/构建事实**：
- embedder 构建（wiki）：`mkdir build && cd build && cmake -DUSER_PROJECT_PATH=examples/flutter-video-player-plugin .. && cmake --build .`
- `flutter-client` CLI（wiki: How-to-run-Flutter-apps）：
  `-b` bundle、`-n` 关光标、`-r` 旋转、`-x/-s` 缩放、`-v` async vblank、
  `-t` title、`-a` app-id、`-k` on-screen keyboard、`-d` decoration、
  `-f` fullscreen、`-w/-h` 尺寸。
  → 加我们的 `--layer-shell/--layer/--anchor/--exclusive-zone/--namespace/--keyboard`
- 不经 flutter-elinux 跑：`./build/<arch>/<mode>/bundle/<app> --help`
- 传自定义参数：`FLUTTER_ELINUX_CUSTOM_RUN_ARGS="--width=640 --height=480" flutter-elinux run -d elinux-wayland`
- app runner CMake：`FLUTTER_TARGET_BACKEND_TYPE` → `-DFLUTTER_TARGET_BACKEND_WAYLAND`；
  wrapper 链 `flutter` + `flutter_wrapper_app`；`${EPHEMERAL_DIR}/flutter_elinux.h`

## 10. 运行时验证的额外障碍（Phase 0 收尾时处理）

- ~~链接需要 `build/libflutter_engine.so`，本机不存在，来源不明~~
  → **已由 §9bis 解决**：放进 CMake build 目录即可，官方有下载 URL。
  本机有 `~/fvm/versions/3.47.4`（Flutter 3.47.4 / Dart 3.13.3），但不是 elinux SDK。
- 替代验证路径（成本从低到高）：
  1. **只验证编译**：`ninja` 到 .o 全通过即可证明 C++ 改造正确（阶段目标）
  2. 装 flutter-elinux SDK → 构建 bundle → 真跑 layer surface
  3. 复用 Rust PoC 的验收截图法（spectacle 可用，grim 不支持 KWin）
- 环境：KWin Wayland，`zwlr_layer_shell_v1 v5`，plasmashell 底栏视觉冲突，
  单屏 eDP-1 1646x1029 logical（scale 1.75，`wl_output.scale` 报整数 2）。

## 11. 待办执行顺序 —— **步骤 1–10 全部完成 ✅**

| # | 任务 | 状态 |
|---|------|------|
| 1 | `pacman -S wayland-protocols` | ✅ 用户执行，1.49 |
| 2 | `libflutter_engine.so` 进 `build/` | ✅ 见 §12 |
| 3 | `mv embedder-upstream embedder` | ✅ 对齐 docs/09 |
| 4 | CMake layer-shell 生成 + sed | ✅ `PATCH_NS_KEYWORD` |
| 5 | `flutter_elinux.h` kLayerShell + 层字段 | ✅ |
| 6 | wrapper `.h` + `.cc` 映射 | ✅ |
| 7 | `elinux_window_wayland.h` 声明 | ✅ |
| 8 | `elinux_window_wayland.cc` 全部逻辑 | ✅ |
| 9 | example CLI | ✅ 6 个新选项 |
| 10 | configure + ninja | ✅ 55/55 .o + 链接 |
| 11 | 文档验收状态 | ✅ §12 |

**剩余**：~~真实 Flutter bundle（§13 决策点）→ 才能出画面（Phase 0 #7 视觉验收）~~
→ **已解除 ✅**，见 §12「真实 bundle 视觉验收」。**Phase 0 全部完成。**

## 12. 验收记录（2026-09-24）

### 编译 / 链接
```
cmake -G Ninja -DCMAKE_BUILD_TYPE=Debug -DUSER_PROJECT_PATH=examples/flutter-wayland-client -B build
ninja -C build          # 55/55 .o，0 error，3 warning 全是上游 wstring_convert 弃用
                        # flutter-client 12.9MB 链接成功
LD_LIBRARY_PATH=build ./build/flutter-client --help   # 6 个新 layer 选项全部出现
```
- **顺带修复**：clang 22 不再传递包含 `<cstdint>`，给 `client_wrapper` 16 个文件补
  `#include <cstdint>`（上游与新 clang 的既有问题，与 layer-shell 无关）。
- **顺带修复**：`LayerShellProperties` 匿名 typedef 触发
  `-Wnon-c-typedef-for-linkage` → 改成 `typedef struct LayerShellProperties {...}`。

### 运行时（假 bundle，engine 在 AOT 阶段即退出，但 layer 路径已走完）
> ⚠️ **日志级别默认 WARNING**，要看到我们自己的 INFO/TRACE 必须
> `FLUTTER_LOG_LEVELS=TRACE`（`logger.cc`，环境变量 `FLUTTER_LOG_LEVELS`）。

```
LD_LIBRARY_PATH=build FLUTTER_LOG_LEVELS=TRACE ./build/flutter-client \
  -b <bundle> --layer-shell -w 0 -h 48 -L 1 -A 14 -e 48 -N materde-shelf -y 0
```
实测输出（KWin / eDP-1）：
```
[TRACE] Created the Wayland surface: 1280x720                 # 占位尺寸
[INFO]  Created the layer surface: layer=1, anchor=14,
        exclusive_zone=48, keyboard_interactivity=0           # shelf 规格正确
[INFO]  Display output info: width = 2880, height = 1800, refresh = 90000
[INFO]  Display scale for output(13): 2
[INFO]  zwlr_layer_surface_v1_listener.configure: 1646x48     # ✅ 全逻辑宽 × shelf 高
[INFO]  layer surface resized to 1646x48                      # ✅ ack + 回写生效
```
**结论**：registry 绑定 `zwlr_layer_shell_v1` → `get_layer_surface` → commit →
KWin 回 configure → ack → 回写 `view_properties_` + `request_redraw_`，
**与 Rust PoC 的 `configure 1646x48` 完全一致**。docs/08 风险 #1（上游无 layer-shell）已覆盖。

### 单位事实（踩过的坑）
- `wl_output.mode` 给的是 **物理** 2880×1800；`wl_output.scale` 报整数 **2**；
  但 layer `configure` 给的是 **逻辑 1646**（= 2880 / 1.75 真实缩放）。
- ⇒ 占位 EGL 尺寸**不能**再乘 `current_scale_`，否则变 5760。已在代码里修。
- ⇒ `display_max_width_` 在 `CreateRenderSurface` 时还是 0（registry 的 wl_output
  事件要第二个 roundtrip 才到），所以实际走的是 `1280x720` 兜底，configure 再纠正。
- 分数缩放 1.75：embedder 只认整数 scale=2 → 渲染 3292 buffer px 显示在 2880 物理上，
  **略微超采样（偏软但正确）**，upstream 的既有行为，不是本 fork 引入的。

### 关键运行事实（以后别再踩）
| 事实 | 值 |
|---|---|
| 日志级别 | `FLUTTER_LOG_LEVELS=TRACE\|DEBUG\|INFO\|WARNING\|ERROR`，**默认 WARNING** |
| bundle 结构 | `<bundle>/data/flutter_assets`、`<bundle>/data/icudtl.dat`、`<bundle>/lib/libapp.so` |
| loader 路径 | `CMAKE_SKIP_RPATH=true` ⇒ 必须 `LD_LIBRARY_PATH=build` |
| 截图 | `grim` 不支持 KWin，用 `spectacle -b -n -o <path>` |
| 假 bundle 现成的 | `/tmp/opencode/fakebundle`（含真实 `icudtl.dat`，来自 `elinux-common.zip`） |
| `pkill -f "build/..."` | ⚠️ 会匹配外层 shell 自身命令行把它杀掉（输出凭空消失）。用 `pkill -x flutter-client` |
| 后台跑 client | `nohup ... & echo "pid=$!"; sleep N; cat log` 放同一条命令里，否则 harness 可能回收子进程 |

### 真实 bundle 视觉验收（Phase 0 #7 ✅，2026-09-24）

工具链按 §13 **方案 A** 落地（Flutter 3.29.3 / Dart 3.7.2 / engine `cf56914b32`，
SDK 在 `~/flutter-elinux`），`shell/` 降级到 Dart `^3.7.0` +
`material-color-utilities 0.11.1` + `flutter_lints ^5.0.0`（6.0.0 要 Dart 3.8）。
7 个 elinux artifact zip 本地化到 `/tmp/opencode/`，
用 `ELINUX_ENGINE_BASE_LOCAL_DIRECTORY=/tmp/opencode` 免重下。

**验收命令与输出**：
```
ELINUX_ENGINE_BASE_LOCAL_DIRECTORY=/tmp/opencode ~/flutter-elinux/bin/flutter-elinux \
  build elinux --release            # → shell/build/elinux/x64/release/bundle/

LD_LIBRARY_PATH=build FLUTTER_LOG_LEVELS=INFO ./build/flutter-client \
  -b <bundle> --layer-shell -w 0 -h 48 -L 1 -A 14 -e 48 -N materde-shelf -y 0
# Created the layer surface: layer=1, anchor=14, exclusive_zone=48, keyboard_interactivity=0
# configure: 1646x48 → layer surface resized to 1646x48（两次 configure）
```
**截图**：`docs/assets/shelf-phase0-acceptance.png`
（2880×1800，底部 84 物理 px = 48 逻辑 × 1.75 全宽 `#CFBCFF` = 主题 `primary`，
非 band 区域是桌面壁纸色，边界在 y=1717）。

**同场验证的三条 docs/07 Verification**：
1. ✅ layer surface 上渲染出 colored rectangle（上图，全宽 primary）
2. ✅ Material You 主题从 seed 生成 —— overlay 探针（800×360 / layer=3 / anchor=5）
   看到 primary 色块 + `onPrimary` 文字 + 6 个 seed 色板 + 亮度按钮
3. ✅ 改 seed → 主题更新 —— `MATERDE_SEED=#006A6A` 重启后整套角色重算
   （`/tmp/opencode/shots/teal_crop.png`：primary 变青、选中勾移到青色板）

**调试过程沉淀（避免重走）**：
- shelf 48px 高度装不下验收页（`Column` 的 `Expanded` 被挤成 0、控制区溢出），
  只剩 `surfaceContainer` 底色。⇒ `_HomeView` 加 `LayoutBuilder`：
  `maxHeight < 220` 时直接返回 `ColoredBox(scheme.primary)`（正是 docs/07 要的色块）。
- 判定"渲染了但不是色块" vs "没渲染"的方法：给视口画 `MediaQuery.sizeOf` 红字，
  一次截图同时回答 metrics 是否正确 + 内容是否 paint（拿到 `1646x48 dpr=2.00` 即证）。
  验收前必须清掉该诊断（`strings libapp.so | grep -c metricsTag` 应为 0）。
- **并行 shell 调用会让截图与重建赛跑**：截到旧 `libapp.so` 的画面（还带红字）。
  重建 + 启动 + 截图必须**串行**在同一条命令里，且先 `md5sum libapp.so` 留证。
- 短视口探针（800×100 / 800×48）在 bottom layer 会被 plasmashell/终端盖住，
  要看小 surface 就用 `-L 3 -A 5`（overlay + top|left）。

## 13. 工具链决策 —— **已拍板并执行：方案 A ✅（2026-09-24）**

> **结论**：采用 **A = flutter-elinux `main` → Flutter 3.29.3 / Dart 3.7.2 /
> engine `cf56914b32`**，已装在 `~/flutter-elinux`（仓库外，避免污染 git），
> release bundle 构建 + 真实 layer surface 渲染全部跑通，Phase 0 #7 验收见 §12。
> 下面保留原始分析与 B/C/D 供以后升级版本时参考。

**硬约束**：surface 只有在 Flutter 真正渲染、commit 一个 buffer 后才会**可见**。
engine 卡在 AOT（没有 `libapp.so`）⇒ 永远黑屏 ⇒ Phase 0 #7「看到色块」无法验收。
所以必须有一条能产出 elinux bundle 的 Flutter 工具链。

**版本对齐现状**（原始调研，全部已实测）：
| 来源 | Flutter | engine artifact |
|---|---|---|
| 本机 fvm | **3.47.4**（Dart 3.13.3, 2026-09） | — |
| flutter-elinux `main` ← **选了这个** | **3.29.3** | `cf56914b32` |
| flutter-elinux 最新 release | **3.27.1**（2024-12） | `cb4b5fff73` |
| 早期下到 `build/` 的 engine | ~~3.32.8 / `ef0cd00091`~~ **已作废**（现用 `cf56914b32`） | |

- flutter-elinux **不是完整 SDK**，是包装器：按 `bin/internal/flutter.version`
  `git clone --depth=1 flutter/flutter -b <tag>` 到 `$ROOT/flutter`，
  再按 `bin/internal/engine.version` 下 artifact。改这两行就能换版本。
- 本机 `~/fvm/versions/3.47.4/engine/src` **有引擎源码**，但要 depot_tools +
  `gclient sync`（数 GB）+ gn/ninja 编译，且 flutter-elinux 完全不支持 3.47.4。

**候选方案**：
- **A（推荐）**：flutter-elinux `main` → Flutter **3.29.3** + `cf56914b32`。
  最省、官方对齐。代价：clone Flutter 3.29.3（`--depth=1`）+ 下 cf56914b32 artifact，
  再把 `build/libflutter_engine.so` 换成同版并重链 embedder。
  ⇒ `shell/` 项目要按 3.29.3 写（`material-color-utilities` 版本要跟着降）。
- **B**：Flutter **3.32.8**（engine so 已在手）。改 flutter-elinux 两行版本钉。
  更新，但 flutter-elinux 自定义命令要能对上 3.32.8 的 `flutter_tools` API，**非官方组合**。
- **C**：自建 **3.47.4** 引擎。最贵（数 GB + 长编译），flutter-elinux 还得自己打补丁。
- **D**：不跑真实 bundle，只交编译级验收。（用户否决 —— Phase 0 #7 要求看到色块）

### 执行记录（方案 A 的落地细节）

| 步骤 | 结果 |
|---|---|
| `git clone flutter-elinux` → `~/flutter-elinux` + `setup` | Flutter **3.29.3** / Dart **3.7.2** / framework `ea121f8859` / DevTools 2.42.3 |
| engine `cf56914b32` 的 `elinux-x64-release.zip` | 早已在 `embedder/build/libflutter_engine.so`，md5 `d0c292e33ef0ab6eb8fd5073ba91504d` 对上 ⇒ **无需重下、无需重链 embedder** |
| 7 个 artifact zip 下载被断 | 改吃本地 `/tmp/opencode/elinux-*.zip`（`unzip -t` 全通过），靠 `ELINUX_ENGINE_BASE_LOCAL_DIRECTORY` 注入 |
| `shell/` 降级 | Dart `^3.7.0`、`material_color_utilities 0.11.1`、`flutter_lints ^5.0.0`（6.0.0 要 Dart 3.8） |
| `flutter-elinux create --platforms elinux .` | 生成 `shell/elinux/` 平台目录 |
| `flutter-elinux build elinux --release` | ✅ `lib/libapp.so` 3.2MB AOT + engine so + icudtl + flutter_assets |
| 并发 flutter 命令 | ⚠️ 抢 startup lock 会损坏 CMake 缓存 ⇒ **必须串行**；失败时清 `build/elinux/x64/*/CMakeFiles` 重跑 |

### 仓库合并记录（2026-09-24）

- `embedder/.git`（origin=sony/flutter-embedded-linux，基线 `1653fa6`）已并入
  **materde 主仓库**，变为普通目录；根仓库 origin = `git@github.com:indusy55/materde.git`。
- 与上游的完整差异固化为 `embedder/patches/0001-layer-shell-support.patch`：
  layer-shell 改造（24 文件，+374/-25）、CMake `namespace→ns`、example CLI 6 选项、
  `cstdint` 修复，以及删除上游 CI（`.github/workflows/build-test.yml`）。
- 同步上游方法：clone sony 仓库 → 把上游增量 patch 打到 `embedder/` → 解决冲突 →
  重新 `git diff` 覆盖 `patches/0001`。
- `poc/`（C 版 + Rust 版两个 PoC）验收通过后删除；其唯一未沉淀进本文的事实
  （指针 ENTER/MOTION/LEAVE 输入路由日志、`wl_output.scale` 整数限制）
  已记入 `docs/08-risk-analysis.md` 的 Go/No-Go 证据摘要与风险 #5 验证记录。

## 14. Phase 1 Commit A：动态 input region + 高 surface + 尺寸竞态修复（2026-09-24）

### 动机与设计

48px 高的 surface 放不下 tooltip / 右键菜单（PopupMenu 需要竖向空间）。方案：

- surface 加高到 **248 = 48 可见 bar + 200 透明带**（`-h 248`）。
  EGL 配置带 `EGL_ALPHA_SIZE=8`，Flutter 根画布透明实测可用（透明带透出后面窗口）。
- **视觉**：只画底部 48（`MaterdeShelf`：透明 Scaffold + 底部 ColoredBox）。
- **输入**：动态 `wl_surface.set_input_region` —— 平时只留底部 48
  （透明带点击穿透给后面窗口），菜单打开时恢复整面
  （菜单接收指针 + 点击外部经 barrier 关闭）。
- exclusive 仍是 48（与 surface 高度无关，窗口只让出底部 48）。

### 新增接口

- **C API**：`FlutterDesktopLayerShellSetInputRegion(x, y, w, h)`
  （`public/flutter_elinux.h` 声明，`elinux_window_wayland.cc` 实现；
  w/h ≤ 0 = 整面）。surface-local 逻辑坐标。单视图用文件级
  `g_layer_shell_window` 注册（layer surface 创建时登记、析构清理）。
  set 后立即 `wl_surface_commit + flush`（input region 是双缓冲状态）。
- **-rdynamic**：flutter-client **静态**链接 embedder ⇒ 符号默认只在
  `.symtab`。Dart `DynamicLibrary.process()`（= `dlopen(NULL)`）需要
  `.dynsym` ⇒ `examples/flutter-wayland-client/cmake/user_build.cmake`
  里 `CMAKE_EXE_LINKER_FLAGS += -rdynamic`。验证：
  `nm -D build/flutter-client | grep FlutterDesktopLayerShellSetInputRegion` → `T`。
- **Dart 侧**：`shell/lib/wayland/layer_shell.dart`（封装；符号缺失降级 no-op，
  `flutter test` 不炸）；`MATERDE_UI=shelf` 环境变量切 shelf UI
  （不设 = Phase 0 acceptance 页，`-h 48` 路径仍可复跑）。

### ⚠️ 尺寸竞态 bug（本 commit 修复，Phase 0 埋下）

layer configure 监听器原先只置 `request_redraw_`，由下一轮 `DispatchEvent()`
（~line 1422）消费回传尺寸。两个竞态源：

1. `wl_output.scale` 处理（~line 2104）置**同一标志**，消费顺序不定；
2. `-w 0` 时 `view_properties_.width` 初值 0，标志可能先被以
   `OnWindowSizeChanged(0, h×scale)` 消费掉。

症状：引擎卡在占位视口 1280×720（逻辑 640 宽）—— 画面上只有左侧
640 逻辑 px（= 1120 物理）有内容，bar 画到视口底 = 屏幕外，exclusive 不生效。
COSMIC 实测**老代码 1/3 全宽**（probe_top 当时连续两次全宽纯属运气）。

**修复**：layer configure 回调内**直接**调
`OnWindowSizeChanged(w×scale, h×scale − decor)`（与 drm 后端 ~line 402 同款），
`DispatchEvent` 循环消费路径保留（scale 变更仍走它）。修复后 **5/5 全宽**。

### 验收记录（2026-09-24，COSMIC，eDP-1 scale 1.75）

- 日志：`configure: 1646x248` → `layer surface resized to 1646x48(248)` →
  `Layer surface input region set to 0,200 1646x48`。
- bar：y1718–1799 整宽一致（82px = 48 逻辑），色 = `surfaceContainer` (33,31,36)。
- 透明带：y1468–1716 透出后面窗口/墙纸原色（差值 1.70）。
- exclusive：窗口止于 y1716，bar 从 y1718 起。
- 点击穿透：人肉点 bar 正上方窗口有反应 ✓。
