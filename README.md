# 多显示器切换工具（AutoHotkey v2）

一个键盘驱动的多显示器切换工具：把鼠标光标切到下一块屏并聚焦该屏的窗口，或者把当前窗口搬到另一块屏。内置全屏游戏处理（先 Alt+Tab 释放光标锁）、防误触校验和看门狗保活。

## 快捷键

| 快捷键 | 作用 |
|---|---|
| `Ctrl+Shift+Q` | 光标切到下一块显示器，并聚焦该屏最上层窗口 |
| `Win+Shift+M` / `Win+Shift+→` | 当前窗口移到下一块屏（光标不动） |
| `Win+Shift+←` | 当前窗口移到上一块屏（光标不动） |

## 功能

- 显示器顺序按空间位置：从左到右、从上到下，最后一块之后循环回第一块。
- 光标落在目标屏工作区中心（自动避开任务栏）。
- 全屏游戏：检测到全屏前台时，先等修饰键松开、发送一次 `Alt+Tab` 让游戏松开光标，再移动光标并聚焦目标窗口；仍失败时会在管理员权限下最小化游戏，切回该屏时会自动恢复。
- 防误触：只在系统层面真正按住 Ctrl+Shift 时才执行，避免修饰键状态残留导致普通 Q 键误触发。
- 看门狗：主脚本每 5 秒写心跳，超过 25 秒没有更新会自动拉起。
- 无托盘图标，不联网。

## 快速开始

1. 下载并解压到任意目录。
2. 双击 `start.bat`。
3. 首次会请求管理员权限，必须允许，否则全屏游戏内无法切出光标。
4. 使用上面的快捷键。

## 开机自启（可选）

右键 `install-autostart.bat` → **以管理员身份运行**。它会创建计划任务 `MonitorSwitchAHK`，登录时以最高权限静默启动，不再弹 UAC。

卸载自启：

```bat
schtasks /delete /tn MonitorSwitchAHK /f
```

## 停止

双击 `stop.bat`（会结束所有 `AutoHotkey64.exe` 进程）。

## 文件说明

- `AutoHotkey64.exe`：AutoHotkey v2 运行时（GPLv2）
- `switch_cursor_monitor.ahk`：光标切屏 + 聚焦窗口
- `switch_monitor.ahk`：窗口搬屏（不移动光标）
- `switch_cursor_watchdog.ahk`：看门狗
- `start.bat` / `stop.bat` / `install-autostart.bat`
- `LICENSE-AutoHotkey.txt`：AutoHotkey 运行时许可证

## 注意

- 仅支持 Windows 10/11。
- 部分带反作弊的游戏会拦截模拟输入或前台切换；脚本已内置管理员与 Alt+Tab 方案，但不能保证兼容所有游戏。
- 全屏游戏切换时可能短暂触发 Alt+Tab 或最小化游戏，这是为了让游戏释放鼠标捕获。
- 运行日志默认关闭，不会写入磁盘。

## 许可

脚本以 GPLv2 发布；随包的 AutoHotkey 运行时同样为 GPLv2，见 `LICENSE-AutoHotkey.txt`。
