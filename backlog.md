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

- [x] ~~`_input` 全局吞键~~ **已修**（`abd304a`）：`scripts/page_nav.gd:73-85` 现在只在「可见且启用输入」时吞键，隐藏/停用后原样返回；新增断言 `hidden_nav_does_not_consume`。
- [ ] **导航守卫是假的**（`scripts/main.gd:123-134`）：`_active_navigation_count()` 只硬编码 `$BookPage/PageNav` 与 `_scene_nav` 两个实例，配 `expected_nav_count` 断言。将来给 `MapPage`/`BattlePage` 加 PageNav，「隐藏页偷吃输入」的自查仍会 PASS。**加第二个 PageNav 的那张卡必须先把这里改成动态扫描。**

## 数值 / 状态（SP-05 起）

- [x] ~~`is_equal_approx` 与 flush 粒度隐式耦合~~ **已修**（`47884e5`）：改成固定 `const VITAL_EPSILON: float = 1e-6`（`scripts/gamestate.gd:8`），与 `drain_flush_threshold` 解耦；新增断言 `epsilon_flush_not_swallowed` / `epsilon_ignores_tiny_change`。
- [x] ~~冻结位挂在 `show_page` 上~~ **已修**（`47884e5`）：改由边界驱动——`scripts/gamestate.gd` 新增 `enter_battle()` / `exit_battle()`，`scripts/main.gd:76-85` 只在真正进出战斗页时调用；新增断言 `freeze_survives_page_switch`。
- [ ] **`--sp04-demo=` 手测钩子已被真消耗覆盖**（`scripts/main.gd:51-61` → `scripts/vital_bar.gd:132` 连了 `vital_changed`）：设 60 之后最多 0.125 秒就被 0.08/s 弹回去，「设完停住」的手测前提不成立。后续截图验收不要再依赖它。
- [x] ~~`_process → drain_time` 接线无断言~~ **已修**（`abd304a`）：`scripts/sp05_test.gd` 新增 `auto_drain_via_process`，放开 `_process` 等真实帧，期望值按旋钮速率算（`expected_drop=0.080025`，容差取 `drain_flush_threshold`）。
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

- [x] ~~**死胡同「无文字」断言恒真**~~ **已修**（`abd304a`）：`scripts/map_grid.gd` 抽出 `get_drawn_labels()`，`_draw()` 与断言 `deadend_draws_no_text` 共用同一数据源，不再是「断言查 Label、绘制走 draw_string」两条路。
- [ ] **`hover_unrevealed` 断言被「非邻」污染**（`scripts/map_grid.gd:304-305`）：point1 与 point5 既不邻接又未揭开，两条件同时成立，分不清哪条规则在起作用。现规则下「未揭开但相邻」不存在，注释写明该断言只作冗余保险即可。
- [ ] **容差口径与卡不符**（`scripts/map_grid.gd:347`）：卡要求 1e-6，实现用 `is_equal_approx`（≈8.8e-4）。实值为精确 88.000000，结论不受影响。
- [ ] **页面隐藏时仍每帧重绘**（`scripts/map_grid.gd:29-31`）：无 `is_visible_in_tree()` 守卫，全流程空转 `queue_redraw`。
- [ ] **地图区起止位置与「上半旁白框缺失」**（`scenes/ui/MapPage.tscn:21-27` 锚点 0.05/0.48/0.89/0.92；GDD `Double_Face_GDD_序章.md:138` 要求「上半旁白文本框 + 下半手绘地图」）。现状：地图已收窄到下半页（`8ca67e1`），但**上半的旁白框在 MapPage 里根本不存在**（全工程只有 `BookPage.tscn:44-67` 的 NarrationFrame）。
  **用户拍板（2026-10-26）**：这一轮**不补**，等做剧情 / 调查文字卡（SP-09、SP-11）时一起放进去；在那之前地图页上半保持空白，后续卡别再重复提这件事。
- [ ] **悬停亮只验了 id、没验颜色**（`scripts/map_grid.gd:351`）：`hover_adjacent` 只断言 `get_hovered_node_id() == &"point2"`；实测悬停前后 `#443b2c → #696256`（`hover_brightness=0.2`）没有进入断言，改暗也全绿。
- [x] ~~**`map_grid.gd` 已 406 行、自测内嵌约 145 行**~~ **已修**（`29c1ddd`）：自测搬到 `scripts/map_grid_selftest.gd`（252 行，`extends RefCounted` + `run(map)`），`scripts/map_grid.gd` 现 349 行、最长函数 25 行，断言 30 条逐字保留。
- [ ] **SP-05 回归命令必须写对**：`-- --sp05-self-test` 跑主场景是**零断言空跑**（自测挂在 `res://scenes/dev/SP05Test.tscn`，`scripts/sp05_test.gd:15`）；正解 `godot --headless --path <工程> res://scenes/dev/SP05Test.tscn --quit-after 200 -- --sp05-self-test`。三条回归命令应写进卡面。
- [ ] **白点色值曾与纸面同值**：`data/map.json:15` 原为 `#f2ebd6` ＝纸面底色，点5 静止时看不见；SP-06 返工中修（恒描边 + 换浅色）。将来换美术素材重排色板时，别再让任何点位色与底色相等。
- [ ] **点旁名字已废，改名改成左上角角标**（`72ab4bd`）：等距方格后 pitch 仅 55–58px，点旁文字会夹在两点之间并压连线（放大 5 倍才认得出，取证图 `_verif\sp06_names.png` + `sp06_names_zoom.png`）。现改为 `scenes/ui/MapPage.tscn` 的 `CurrentPointLabel`（左上 `offset 12/8`、字号 16、`#443b2c`），文本 `当前位置：<名字>`；`scripts/map_grid.gd` 内 `draw_string` 调用数已为 0。用户拍板（2026-10-26）。
- [ ] **c1 / d1 / d2 三个点没有名字**：`data/map.json` 里它们是 `plain` 色、无名字字段，角标按 id 原文显示（`当前位置：c1`）。要不要给它们起名字属于内容设定，**等剧情/调查文字卡（SP-09、SP-11）再定**，本轮不编。
- [ ] **角标宽度是 Label 自适应最小尺寸**（实测 248px，右边界 x=324），名字最多撑到接近 `entry_exit` 的「入口/出口」。将来名字变长（超过约 12 个全角字）会撞到最左的点（x≈490），届时需要限宽 + 换行或缩字号。

## 全量代码审查（2026-10-27，独立只读会话 codex-4 · gpt-6-astra/high）

范围：全部脚本 + 场景 + 数据，只读不改。基线：SP-06 30 / SP-03 17 / SP-04 13 / SP-05 15 PASS，四组 failures=0、无 SCRIPT ERROR。

### 已修（8 条 P1，分两批，各自过独立复审后才提交）

批 A（47884e5）：
- 嗓子为 0 仍能走 / 能查（gamestate.gd 的 _spend 不查余额）→ 余额不足即拒；新增断言 no_step_at_zero / no_point_at_zero / no_step_when_insufficient / step_at_exact_balance。
- epsilon 与 flush 粒度耦合、冻结位挂在 show_page —— 见上文对应条目（均已标已修）。

批 B（abd304a）：
- PageNav 全局吞键、SP-05 自动扣点无断言、死胡同断言恒真 —— 见上文对应条目（均已标已修）。
- 布局等待失败仍 exit 0（main.gd）→ 新增 --sp03-force-layout-fail；失败计入 _failures 并 quit(1)；实测 failures=1 且退出码 1。
- 键盘断言绕过事件链（map_grid.gd）→ 改 get_viewport().push_input(InputEventKey)，按下 / 释放成对；断言 keyboard_event_pending / keyboard_event_confirm_move。

规范（29c1ddd）：map_grid.gd 530 → 349 行，自测拆到 map_grid_selftest.gd（252 行），断言 30 条逐字保留。

### 仍未修（P2 十条，留待 SP-07 开工前统一处理）

- data/map.json:3 的 start_id 不生效：scripts/map_grid.gd:7 仍用常量 START_ID，改 JSON 没反应。
- data/map.json 无 schema 校验：字段拼错只在运行期暴露；缺 id 时静默跳过。
- 地图页隐藏时仍每帧 queue_redraw（scripts/map_grid.gd:29-31，无 is_visible_in_tree() 守卫）。
- scripts/page_nav.gd 每帧全量扫描 + 排序（见「性能」段）。
- 场景硬连 confirmed → mark_used（scenes/ui/BookPage.tscn:119、scenes/ui/NavGridTest.tscn:53）。
- SP-04 闪光期绘制色无断言（scripts/vital_bar.gd 里 lightened(0.22) 改小仍全绿）。
- VitalBar 文案两份真源（场景静态 text="100" 与脚本 get_display_text()）。
- scripts/main.gd:121-123 忽略布局等待的返回值（SP-03 / SP-04 已加 force 检查，此处未检）。
- project.godot:24-27 默认字号设置无效（见「视觉」段第 2 条）。
- scenes/ui/MapPage.tscn:55 mouse_filter=0 + scripts/map_grid.gd 的 _gui_input 内 accept_event()：左键在整页被吞，将来叠加对话框 / 按钮会抢不到点击。

### 证据口径（写给以后的卡）

- 只有「重要节点」（用户 2026-10-27 定：**地图数据加载与校验**、**存档与读档**）才要求「故意改坏 → 变红 → 恢复 → 变绿」的实证；其余改动只要自检跑绿（PASS 行数正常、`failures=0`）+ 用户试玩没问题就算过，不再要求改坏实证。见 AGENTS.md 第 15 条。
- 退出码不能当门禁：Godot 加了 --quit-after 后，脚本解析失败也 exit 0，必须数 PASS 行与 failures= 行。
- SP-05 回归必须跑 dev 场景（见上文「SP-05 回归命令必须写对」那条）。

---

## 第四组：5 条「结构地雷」清完（2026-10-27 · commit 0e8a667）

上面「仍未修（P2 十条）」整段已被批 C / 批 D / 第四组三轮吃掉，逐条状态如下（终态以本条为准）：

| # | 问题 | 终态 |
|---|---|---|
| 1 | `data/map.json` 的 `start_id` 不生效 | 已修：`scripts/map_grid.gd:155` 加载时用 `_resolve_start_id(raw_map)`；无效/缺失回落 `entry_exit` 并 `push_warning`（`:167-177`），不再整图判死 |
| 2 | 地图数据无结构校验 | 已修：`scripts/map_data.gd:19-96` 校验必填键 / 网格正值 / id 唯一 / 坐标边界 / 边端点 / 颜色枚举；失败即拒绝进入可玩 |
| 3 | 地图页隐藏仍每帧 `queue_redraw` | 已修（批 C） |
| 4 | `page_nav` 每帧全量扫描 | 已修（批 C，改 node_added/removed 增量） |
| 5 | 场景硬连 `confirmed → mark_used` | 已修（批 D：删掉两条 connection，改由 `main.gd` 的 `_on_page_nav_confirmed` 决定） |
| 6 | SP-04 闪光期绘制色无断言 | 已修（批 D：`get_draw_color()` + `expected_draw_color` 断言） |
| 7 | VitalBar 文案两份真源 | 已修（批 D：`THROAT_TEXT` 单一真源 + `get_text_content()`；竖排由 `text_vertical_layout` 断言守住） |
| 8 | 布局等待失败不记 FAIL | 已修：失败记 FAIL 并走 `quit(1)`（`main.gd:123-129`），新增 `layout_wait_failure_recorded` |
| 9 | `project.godot:24-27` 默认字号无效 | 已修（批 D：删掉无效的 `theme/default_font_size`，观感未变） |
| 10 | 地图页左键被整页吞掉 | 已修：`MapPage.tscn:55` `mouse_filter=1`(PASS) + `map_grid.gd:21` `MOUSE_FILTER_PASS`，只在命中点位时 `accept_event()`（`:116-121`） |

### 本轮新增的两条「点击穿透」断言（此前的判据是错的）

- 旧判据 `blank_click_not_consumed` 断言 `get_viewport().is_input_handled() == false`：**永远不可能通过**——地图框下面压着铺满全屏的 `BookPage/Paper`（`mouse_filter=STOP`），点击漏下去就该被纸接住。
- 新判据（已实现并通过）：
  - `blank_click_passes_through`：空白处注入左键 → 下层 `gui_input` 计数器 +1 且地图状态不变；
  - `point_click_consumed`：点位中心注入左键 → 下层计数器不变（被地图吃掉）且光标确实移动了。
- 变异实证：删掉 `accept_event()` → `point_click_consumed` 变红；空白处也 accept → `blank_click_passes_through` 变红。

### 自检基线（第四组后）

| 组 | PASS | failures |
|---|---|---|
| SP-06 | 42 | 0 |
| SP-03 | 19 | 0 |
| SP-04 | 16 | 0 |
| SP-05 | 15 | 0 |

### 剩下的已知风险（不挡事，记录在案）

- `scripts/main.gd` 364 行、`scripts/map_grid.gd` 346 行：离 400 行上限只差三十来行，下次加功能前先拆。
- `_resolve_start_id` 的回落常量写死 `entry_exit`：将来若某张图没有入口点，仍会判不可玩（会 `push_error`，不会静默）。

---

## 用户新增改动名单（2026-10-28，试玩后反馈）

| # | 需求（用户原话） | 状态 | 备注 |
|---|---|---|---|
| U-01 | 「添加一个手动切换页面的按钮」 | 待做 | 现在翻页只认 `PageDown` / `PageUp`（`scripts/main.gd:99-112`），笔记本键盘上这两个键常与 `Fn` 组合、用户按不到；需要一个屏幕上的按钮。按钮形式与位置等用户拍板后再派 `codex-5`。 |

