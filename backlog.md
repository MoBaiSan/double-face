# backlog（待办与挂账）

> 只记「已知但本轮不做」的事，一条一行、写清为什么挂账。
> 换美术素材、开新卡前先看这里。

## 视觉 / 美术（等素材）

- [ ] **选中态看不出选中**（SP-02 截图实证，SP-03 三页布局里依旧成立）：选中描边 `#fff9e5` 对纸底 `#f2ebd6` 只有 1.13:1，未选中 `#443b2c` 是 9.24:1 → 看图会以为「未选中项是选中的」。现为选中 2px / 未选中 1px，只缓解不解决。
  用户决定（SP-03 收尾时）：**不管，后续不再提醒，写进待办即可**。换美术素材时一并处理。
- [ ] **全局默认字号无法靠 project.godot 设**：`project.godot:23` 的 `theme/default_font_size=20` 在 Godot 4.6.2 下不生效（实测 `ProjectSettings.get_setting` 能读到 20，但 `ThemeDB.fallback_font_size` 仍 16、默认 Label 仍 16）。真正生效的是各 Label 显式写的 24px。要全局 20 必须建 Theme 资源 + `gui/theme/custom_theme`。用户已批准「要 20px」，但当前实现方式无效，等开新卡处理。

## 交互 / 输入（SP-03 起必须做）

- [ ] `_input` 全局吞键（`scripts/page_nav.gd:73-85`）：PageNav 可见且有候选时，方向键与确认键一律 `set_input_as_handled()`。一旦叠加对话框 / 设置面板会抢键 → 需引入「活动层」判断。
- [ ] **导航守卫是假的**（`scripts/main.gd:123-134`）：`_active_navigation_count()` 只硬编码 `$BookPage/PageNav` 与 `_scene_nav` 两个实例，配 `expected_nav_count` 断言。将来给 `MapPage`/`BattlePage` 加 PageNav，「隐藏页偷吃输入」的自查仍会 PASS。**加第二个 PageNav 的那张卡必须先把这里改成动态扫描。**

## 已定版式（后续卡不许擅自改）

- **嗓子条占位位置**：贴纸面右缘内侧，`x=1222`、宽 24、右侧留 34px 纸色（用户看过三页截图后拍板「就这样」）。纸面是**满幅出血** `[0,0] 1280×720`，左缘 14px 撕边。SP-04 做真竖刻度时沿用此位置与这段留白。

## 性能 / 代码整洁（顺手时做）

- [ ] `_process` 每帧 `_sync_candidates`（`scripts/page_nav.gd:164-186`）：每帧 `get_nodes_in_group` + `sort_custom` + 数组比较。
- [ ] `mark_used`（`scripts/page_nav.gd:147-151`）候选不在列表时静默失败，不报错。
- [ ] 场景 `layout_mode` 写法不一致（`scenes/ui/BookPage.tscn:69-74/81-92/99-110`、`scenes/ui/NavGridTest.tscn:5-8/10-15/17-24/46-51` 缺）→ 编辑器保存会产生无关 diff。
- [ ] 行尾混用：`scripts/page_nav.gd` 全 LF，`scenes/ui/BookPage.tscn` 存为 CRLF，git 反复提示。
- [ ] 场景硬连 `confirmed → mark_used`（`BookPage.tscn:119`、`NavGridTest.tscn:53`）：测试语义泄进场景，转正式页时必须拆。

## 环境 / 工具

- [ ] codex 沙箱内 `gda` 不可用（`Errno 13` 写日志失败 / `daemon_runtime_unusable`）。现行分工：codex 写码 + headless 自检；截图由宿主侧 `tools\gda_shot.ps1` 做（每次需用户批准，规则第 9 条）。
- [ ] `tools\gda_shot.ps1` 必须带 BOM 与 CRLF 保存，否则 PowerShell 5.1 按 ANSI 读中文会静默报语法错。
