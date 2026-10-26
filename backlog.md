# backlog（待办与挂账）

> 只记「已知但本轮不做」的事，一条一行、写清为什么挂账。
> 换美术素材、开新卡前先看这里。

## 视觉 / 美术（等素材）

- [ ] **选中态看不出选中**（SP-02 截图实证，SP-03 三页布局里依旧成立）：选中描边 `#fff9e5` 对纸底 `#f2ebd6` 只有 1.13:1，未选中 `#443b2c` 是 9.24:1 → 看图会以为「未选中项是选中的」。现为选中 2px / 未选中 1px，只缓解不解决。
  用户决定（SP-03 收尾时）：**不管，后续不再提醒，写进待办即可**。换美术素材时一并处理。
- [ ] **全局默认字号无法靠 project.godot 设**：`project.godot:23` 的 `theme/default_font_size=20` 在 Godot 4.6.2 下不生效（实测 `ProjectSettings.get_setting` 能读到 20，但 `ThemeDB.fallback_font_size` 仍 16、默认 Label 仍 16）。真正生效的是各 Label 显式写的 24px。要全局 20 必须建 Theme 资源 + `gui/theme/custom_theme`。用户已批准「要 20px」，但当前实现方式无效，等开新卡处理。
- [ ] **嗓子条四段色值待用户拍板**：`scripts/vital_bar.gd:12-19` 的 `#217a8a`（充足）/ `#ad6b24`（偏低）/ `#b33b3b`（告急）/ `#4c526b`（断）**无 GDD 出处**，是实现者补的设计值。GDD §3.2 只给了语义（满色／变色／偏红／歌声停）。等用户看四张截图（`_verif\sp04_{100,60,30,0}.png`）确认沿用或换值。
- [ ] **告急档持续闪动未做**：GDD §3.2 告急段（30–1）写的是「条闪动」，SP-04 只做了「下降瞬间 0.15s 闪一次」（怕两种闪混淆）。SP-05 接真数值时也没做，仍未挂账未清。
- [ ] **0 点闪光偏弱**：断态 `#4c526b` → `lightened(0.22)` = `#73788c`，边框两态仅 1.76:1，28% 淡填充两态 1.13:1（等于看不见）。要靠 460px 长的 1px 边框整体变亮才看得出来。要更明显就加粗边框或提幅度。
- [ ] **竖排「唱」底距 Label 下边只有 1px**：`scenes/ui/VitalBar.tscn` 的 ThroatText 6 行 ×16.5px = 99px，被自身最小尺寸顶到 99，字号再大 1px 就会被裁。取证图 `_verif\sp04_text_zoom_framed.png`（红框＝Label 边界）。
- [ ] **闪光期绘制色没有自动断言**：自检比的是 `get_state_color()`，把 `lightened(0.22)` 偷偷改成 0.02 仍然全绿。建议抽一个 `get_draw_color()` 并纳入自检。

## 交互 / 输入（SP-03 起必须做）

- [ ] `_input` 全局吞键（`scripts/page_nav.gd:73-85`）：PageNav 可见且有候选时，方向键与确认键一律 `set_input_as_handled()`。一旦叠加对话框 / 设置面板会抢键 → 需引入「活动层」判断。
- [ ] **导航守卫是假的**（`scripts/main.gd:123-134`）：`_active_navigation_count()` 只硬编码 `$BookPage/PageNav` 与 `_scene_nav` 两个实例，配 `expected_nav_count` 断言。将来给 `MapPage`/`BattlePage` 加 PageNav，「隐藏页偷吃输入」的自查仍会 PASS。**加第二个 PageNav 的那张卡必须先把这里改成动态扫描。**

## 数值 / 状态（SP-05 起）

- [ ] **`is_equal_approx` 与 flush 粒度隐式耦合**（`scripts/gamestate.gd:115` + `:39-40`）：100 点时近似相等门限是 `1e-3`，而 flush 量是 `1e-2`，只有 10 倍余量。将来 `vital_max` 调到 1000 或 flush 调到 0.001，扣点会被**静默吞掉且不报任何错**——正是卡里坑#3「取整吃掉」的变种。应改固定 epsilon（`absf(diff) < 1e-6`）。
- [ ] **冻结位挂在 `show_page` 上**（`scripts/main.gd:81`）：任何翻页都会重设冻结位。将来用浮层进战斗、或剧情里临时冻结，一次翻页就把冻结解了。应改由战斗页自己在进出时调 `set_frozen`。
- [ ] **`--sp04-demo=` 手测钩子已被真消耗覆盖**（`scripts/main.gd:51-61` → `scripts/vital_bar.gd:132` 连了 `vital_changed`）：设 60 之后最多 0.125 秒就被 0.08/s 弹回去，「设完停住」的手测前提不成立。后续截图验收不要再依赖它。
- [ ] **`_process → drain_time` 接线无断言**：自查里用 `set_process(false)` 变纯同步（`scripts/sp05_test.gd:40`），因此「时间真的会自己掉」这条接线没有覆盖。应补一条「放开 `_process` 跑 N 帧、断言累积器按速率增长」的用例。
- [ ] **band 阈值语义变了没钉死**：档位阈值改由旋钮 61/31/1 决定，与 SP-04 旧内联阈值 60/30 在 30.5~31 之间语义不同；SP-04 的四个采样点（0/30/60/100）恰好两边一致，把差异掩盖了。SP-21 数值定稿时必须钉死。
- [ ] **新旋钮 `drain_flush_threshold` 不在卡面 9 个数里**（`data/knobs.json:11`）：SP-21 的旋钮清单（验收 A18）按卡面点数对表，多这一个会对不上，必须在 SP-21 登记。
- [ ] **注释与旋钮脱钩**（`scripts/gamestate.gd:83`）：注释写死「回 10 点」，实际值来自 `battle_win_recovery`；旋钮一改注释就骗人。改成「按 battle_win_recovery 回血」。
- [ ] **`VitalBar.tscn:32` 静态 `text="100"`** 是首帧前的假数（运行时被 `vital_bar.gd:66,133` 覆盖）。留空或写 0，避免以后误读成默认值。

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

## 地图（SP-06 验收挂账）

- [ ] **死胡同「无文字」断言恒真**（`scripts/map_grid.gd:328`）：用 `find_children("*","Label")` 找 Label，但本页全部文字走 `draw_string`（`:257`），Label 永远为空 → 断言恒过。改成对外暴露 `get_notice_text()` 断言为空，或改判「`pay_point` 计数 + vital 不变」为主证据。
- [ ] **`hover_unrevealed` 断言被「非邻」污染**（`scripts/map_grid.gd:304-305`）：point1 与 point5 既不邻接又未揭开，两条件同时成立，分不清哪条规则在起作用。现规则下「未揭开但相邻」不存在，注释写明该断言只作冗余保险即可。
- [ ] **容差口径与卡不符**（`scripts/map_grid.gd:347`）：卡要求 1e-6，实现用 `is_equal_approx`（≈8.8e-4）。实值为精确 88.000000，结论不受影响。
- [ ] **页面隐藏时仍每帧重绘**（`scripts/map_grid.gd:29-31`）：无 `is_visible_in_tree()` 守卫，全流程空转 `queue_redraw`。
- [ ] **地图区起止位置与「上半旁白框缺失」**（`scenes/ui/MapPage.tscn:21-27` 锚点 0.05/0.48/0.89/0.92；GDD `Double_Face_GDD_序章.md:138` 要求「上半旁白文本框 + 下半手绘地图」）。现状：地图已收窄到下半页（`8ca67e1`），但**上半的旁白框在 MapPage 里根本不存在**（全工程只有 `BookPage.tscn:44-67` 的 NarrationFrame）。
  **用户拍板（2026-10-26）**：这一轮**不补**，等做剧情 / 调查文字卡（SP-09、SP-11）时一起放进去；在那之前地图页上半保持空白，后续卡别再重复提这件事。
- [ ] **悬停亮只验了 id、没验颜色**（`scripts/map_grid.gd:351`）：`hover_adjacent` 只断言 `get_hovered_node_id() == &"point2"`；实测悬停前后 `#443b2c → #696256`（`hover_brightness=0.2`）没有进入断言，改暗也全绿。
- [ ] **`map_grid.gd` 已 406 行、自测内嵌约 145 行**（`:262-406`）：SP-07 接入调查后必破 400 行上限。SP-07 前必须照 SP-05 的模式拆到 `scenes/dev/` + `scripts/`。
- [ ] **SP-05 回归命令必须写对**：`-- --sp05-self-test` 跑主场景是**零断言空跑**（自测挂在 `res://scenes/dev/SP05Test.tscn`，`scripts/sp05_test.gd:15`）；正解 `godot --headless --path <工程> res://scenes/dev/SP05Test.tscn --quit-after 200 -- --sp05-self-test`。三条回归命令应写进卡面。
- [ ] **白点色值曾与纸面同值**：`data/map.json:15` 原为 `#f2ebd6` ＝纸面底色，点5 静止时看不见；SP-06 返工中修（恒描边 + 换浅色）。将来换美术素材重排色板时，别再让任何点位色与底色相等。
