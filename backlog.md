# backlog（待办与挂账）

> 只记「已知但本轮不做」的事，一条一行、写清为什么挂账。
> 换美术素材、开新卡前先看这里。

## 视觉 / 美术（等素材）

- [ ] **选中态看不出选中**（SP-02 截图实证）：选中描边 `#fff9e5` 对纸底 `#f2ebd6` 只有 1.13:1，未选中 `#443b2c` 是 9.24:1 → 看图会以为「未选中项是选中的」。现为选中 2px / 未选中 1px，只缓解不解决。用户决定：先这样，**换素材时一并处理**。

## 交互 / 输入（SP-03 起必须做）

- [ ] `_input` 全局吞键（`scripts/page_nav.gd:73-85`）：PageNav 可见且有候选时，方向键与确认键一律 `set_input_as_handled()`。一旦叠加对话框 / 设置面板会抢键 → 需引入「活动层」判断。

## 性能 / 代码整洁（顺手时做）

- [ ] `_process` 每帧 `_sync_candidates`（`scripts/page_nav.gd:164-186`）：每帧 `get_nodes_in_group` + `sort_custom` + 数组比较。
- [ ] `mark_used`（`scripts/page_nav.gd:147-151`）候选不在列表时静默失败，不报错。
- [ ] 场景 `layout_mode` 写法不一致（`scenes/ui/BookPage.tscn:69-74/81-92/99-110`、`scenes/ui/NavGridTest.tscn:5-8/10-15/17-24/46-51` 缺）→ 编辑器保存会产生无关 diff。
- [ ] 行尾混用：`scripts/page_nav.gd` 全 LF，`scenes/ui/BookPage.tscn` 存为 CRLF，git 反复提示。
- [ ] 场景硬连 `confirmed → mark_used`（`BookPage.tscn:119`、`NavGridTest.tscn:53`）：测试语义泄进场景，转正式页时必须拆。

## 环境 / 工具

- [ ] codex 沙箱内 `gda` 不可用（`Errno 13` 写日志失败 / `daemon_runtime_unusable`）。现行分工：codex 写码 + headless 自检；截图由宿主侧 `tools\gda_shot.ps1` 做（每次需用户批准，规则第 9 条）。
- [ ] `tools\gda_shot.ps1` 必须带 BOM 与 CRLF 保存，否则 PowerShell 5.1 按 ANSI 读中文会静默报语法错。
