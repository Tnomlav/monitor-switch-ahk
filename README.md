# MonitorSwitch

MonitorSwitch 是面向 Windows 10/11 的多显示器快捷工具，用于快速切换鼠标光标或移动当前窗口。它适合多屏办公、窗口整理以及全屏和 Unity 游戏场景。

## 快捷键

| 快捷键 | 功能 |
|---|---|
| `Ctrl+Alt+C` | 将光标切到下一块显示器，并聚焦该屏最上层窗口 |
| `Ctrl+Alt+M` | 将当前窗口移到下一块显示器，不移动光标 |
| `Ctrl+Alt+→` | 将当前窗口移到下一块显示器 |
| `Ctrl+Alt+←` | 将当前窗口移到上一块显示器 |

快捷键不使用 `Shift`，避免输入法将组合中的 Shift 误判为中英文切换。

## 主要特性

- 显示器按空间位置从左到右、从上到下排序，末尾自动循环。
- 光标落在目标屏幕工作区中心，自动避开任务栏。
- 搬移窗口时不移动鼠标光标。
- 支持最大化窗口、不同 DPI 缩放和无边框窗口。
- 支持全屏与 Unity 游戏：需要时先释放游戏前台，移动窗口后再重新激活。
- 使用系统热键、Raw Input 和物理按键轮询，降低游戏输入通道拦截热键的概率。
- 连续按键会合并处理，避免一次操作重复执行。
- 主脚本带有心跳看门狗，异常退出后可以自动重新启动。
- 启动器自动请求管理员权限，以兼容以管理员身份运行的游戏。

## 快速开始

1. 下载最新版压缩包并完整解压。
2. 双击 `MonitorSwitch.exe`。
3. 在 UAC 提示中选择“是”。
4. 使用上表中的快捷键。

也可以运行 `start.bat`。启动器会自动查找同目录或 `v2` 子目录中的 AutoHotkey 运行时。

## 开机自启

右键 `install-autostart.bat`，选择“以管理员身份运行”。脚本会创建计划任务 `MonitorSwitchAHK`，在登录时以最高权限启动。

删除自启任务：

```bat
schtasks /delete /tn "MonitorSwitchAHK" /f
```

## 自定义按键

游戏通常同时读取 Raw Input，固定组合键可能与游戏按键冲突。推荐将脚本绑定到：

- 鼠标侧键 `XButton1` / `XButton2`
- 键盘扩展键 `F13`–`F24`
- 宏键盘或自定义按键设备

也可以在 G HUB、Ulanzi Studio 等设备软件中，把设备按键映射为 `Ctrl+Alt+C` 或 `Ctrl+Alt+M`。

直接修改 AHK 热键时，请同步调整脚本中的 `ctrlDown`、`altDown` 校验，避免被防误触逻辑拦截。

## 停止与日志

- 双击 `stop.bat` 可结束全部 `AutoHotkey64.exe` 进程。
- 光标切换默认不写详细日志，只保留启动、退出和错误记录。
- 窗口搬屏日志位于 `switch_monitor.log`。

## 文件说明

- `MonitorSwitch.exe`：自动提权启动器
- `AutoHotkey64.exe`：AutoHotkey v2 运行时
- `switch_cursor_monitor.ahk`：光标切屏与窗口聚焦
- `switch_monitor.ahk`：窗口搬屏
- `switch_cursor_watchdog.ahk`：光标脚本看门狗
- `start.bat`、`stop.bat`、`install-autostart.bat`：启动、停止和自启脚本
- `launcher/Program.cs`：启动器源码

## 兼容性说明

- 支持 Windows 10/11。
- 部分反作弊游戏会拦截模拟输入或前台切换。程序提供系统热键、Raw Input、Alt+Tab 和窗口位置重试，但无法保证兼容所有游戏。
- 搬到管理员游戏窗口时，本程序也需要管理员权限。
- 如果无边框窗口仍被游戏拉回原屏，可先尝试游戏的“窗口”显示模式。

## 许可

脚本采用 GPLv2 发布；随包的 AutoHotkey 运行时同样遵循 GPLv2，详见 `LICENSE-AutoHotkey.txt`。
