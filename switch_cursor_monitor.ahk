#Requires AutoHotkey v2.0
#SingleInstance Force
#MaxThreadsPerHotkey 1
#MaxThreadsBuffer 0
#UseHook True
#NoTrayIcon

; =====================================================================
;  Ctrl+Shift+Q
;
;  把鼠标光标切到“下一台显示器”，并把该显示器最上层的窗口切到前台。
;
;  · 显示器顺序：按空间位置，从左到右、从上到下；最后一台之后回到第一台。
;    连续按键一定是 1→2→3→1→2→3，不会重复同一台。
;  · 光标落点：目标显示器工作区的中心（自动避开任务栏）。
;  · 目标窗口：该显示器上可见、最靠前的普通顶层窗口（相当于 Alt+Tab 里的第一个）。
;  · 如果当前前台程序（例如独占全屏游戏）锁定了鼠标，脚本会先激活目标显示器
;    上的窗口。如果目标屏幕没有普通窗口，则先激活任务栏，然后再移动光标。
;  · 这样会主动让游戏失去前台焦点，不需要手动按 Alt+Tab。
;
;  启动方式：
;    "C:\TOOLS\AutoHotKey\v2\AutoHotkey64.exe" "C:\TOOLS\AutoHotKey\switch_cursor_monitor.ahk"
; =====================================================================

; 调试日志：设为 true 后每次按键会写 switch_cursor_monitor.log
DEBUG := false

; 全屏游戏一般是高权限进程，普通权限抢不到它的前台和光标锁。
; 想在这种情况下也生效，把这里改成 true（启动时会弹一次 UAC）。
RUN_AS_ADMIN := true
if (RUN_AS_ADMIN && !A_IsAdmin) {
    try Run('*RunAs "' A_AhkPath '" "' A_ScriptFullPath '"')
    ExitApp
}

; ---- 常驻脚本的可观测性 ----
; 保留托盘图标：能一眼看出脚本是否还在，双击可重新加载
A_IconTip := "切换显示器：Ctrl+Shift+Q（双击这里重新加载）"
A_TrayMenu.Delete()
A_TrayMenu.Add("重新加载", (*) => Reload())
A_TrayMenu.Add()
A_TrayMenu.Add("退出", (*) => ShutdownFromTray())
A_TrayMenu.Default := "重新加载"

; 心跳文件：看门狗脚本据此判断本脚本是否还活着
HeartbeatFile := A_ScriptDir "\switch_cursor_heartbeat.txt"
StopFlagFile := A_ScriptDir "\switch_cursor_stopped.flag"
try FileDelete(StopFlagFile)          ; 正常启动即解除“用户主动退出”标记
Heartbeat()
SetTimer(Heartbeat, 5000)

OnError(LogError)
OnExit(LogExit)
LogAlways("启动 pid=" ProcessExist())

Heartbeat() {
    global HeartbeatFile
    try {
        file := FileOpen(HeartbeatFile, "w")
        if (file) {
            file.Write(FormatTime(, "yyyy-MM-dd HH:mm:ss"))
            file.Close()
        }
    }
}

ShutdownFromTray() {
    global StopFlagFile
    try {
        file := FileOpen(StopFlagFile, "w")
        if (file) {
            file.Write("stopped " FormatTime(, "yyyy-MM-dd HH:mm:ss"))
            file.Close()
        }
    }
    ExitApp()
}

LogAlways(text) {
    try FileAppend(FormatTime(, "yyyy-MM-dd HH:mm:ss") "  " text "`n",
        A_ScriptDir "\switch_cursor_monitor.log", "UTF-8")
}

LogError(err, mode) {
    LogAlways("错误 [" mode "] " err.Message " @ " err.What " line " err.Line)
    return true   ; 吞掉错误，热键线程退出但脚本继续常驻
}

LogExit(*) {
    LogAlways("退出")
    return 0
}

Log(text) {
    global DEBUG
    if (!DEBUG)
        return
    try FileAppend(FormatTime(, "HH:mm:ss") "  " text "`n",
        A_ScriptDir "\switch_cursor_monitor.log", "UTF-8")
}

Log("script loaded")

switchQueue := []
switchRunning := false

^+q::RequestSwitch()

; 热键线程只负责“收请求”：校验真实修饰键、吞掉长按重复、把请求入队。
RequestSwitch() {
    global switchQueue, switchRunning

    ; 防止 AHK 修饰键状态残留：以系统真实按键状态为准。
    ctrlDown := DllCall("GetAsyncKeyState", "Short", 0x11) & 0x8000
    shiftDown := DllCall("GetAsyncKeyState", "Short", 0x10) & 0x8000
    if (!ctrlDown || !shiftDown)
        return

    ; 等物理 Q 松开：长按产生的自动重复会被吞掉，每次真实按键只入队一次。
    KeyWait "q"

    Critical
    switchQueue.Push(true)
    if (!switchRunning) {
        switchRunning := true
        SetTimer(ProcessQueue, -10)
    }
    Critical "Off"
}

; 队列消费者：一次处理一个请求，快速连按会依次执行而不是被丢弃。
ProcessQueue() {
    global switchQueue, switchRunning

    Critical
    if (!switchQueue.Length) {
        switchRunning := false
        Critical "Off"
        return
    }
    switchQueue.RemoveAt(1)
    Critical "Off"

    PerformSwitch()

    Critical
    if (switchQueue.Length)
        SetTimer(ProcessQueue, -50)
    else
        switchRunning := false
    Critical "Off"
}

PerformSwitch() {

    ; 多屏缩放比例不同时按物理像素取坐标，避免光标落点偏移
    try DllCall("SetThreadDpiAwarenessContext", "Ptr", -4)  ; PER_MONITOR_AWARE_V2

    monitors := GetMonitors()
    if (monitors.Length < 2) {
        ShowTip("只检测到 1 台显示器")
        return
    }

    ; ---- 当前光标所在显示器 ----
    pt := Buffer(8, 0)
    DllCall("GetCursorPos", "Ptr", pt)
    curX := NumGet(pt, 0, "Int")
    curY := NumGet(pt, 4, "Int")

    curIdx := 1
    for i, m in monitors {
        if (curX >= m.left && curX < m.right && curY >= m.top && curY < m.bottom) {
            curIdx := i
            break
        }
    }

    ; ---- 下一台（循环） ----
    ; 用明确的序号推进：连续按键一定是 1→2→3→1→2→3，不会受光标被别的程序
    ; 拽回、或落点不精确的影响。第一次按键从光标所在屏开始。
    static idx := 0
    if (idx < 1 || idx > monitors.Length)
        idx := curIdx
    idx := Mod(idx, monitors.Length) + 1
    nextIdx := idx
    target := monitors[nextIdx]

    Log(Format("press cursor={1},{2} count={3} curIdx={4} nextIdx={5}"
        , curX, curY, monitors.Length, curIdx, nextIdx))
    for i, m in monitors
        Log(Format("   mon{1}: {2},{3} -> {4},{5}", i, m.left, m.top, m.right, m.bottom))

    ; ---- 判断方向：离开全屏游戏，还是切入全屏游戏 ----
    ; 目标窗口必须在移动光标之前激活。否则独占全屏游戏会继续持有前台焦点，
    ; 并在每一帧把光标拉回游戏中心。
    foregroundBefore := DllCall("GetForegroundWindow", "Ptr")
    leavingFullscreen := foregroundBefore && IsFullscreenWindow(foregroundBefore)

    ; 全屏游戏会持续锁光标/抢前台，先 Alt+Tab 让出焦点，再移动光标。
    ; 等物理 Ctrl/Shift 松开，避免 Alt+Tab 被识别成 Ctrl+Alt+Tab。
    if (leavingFullscreen) {
        KeyWait "Ctrl", "T0.6"
        KeyWait "Shift", "T0.6"
        Sleep 30
        SendInput("!{Tab}")
        Sleep 260
        Log("   sent Alt+Tab to release fullscreen foreground")
    }

    hwnd := FindTopWindowOnMonitor(target, leavingFullscreen)
    enteringFullscreen := hwnd && IsFullscreenWindow(hwnd)

    posX := target.workLeft + (target.workRight - target.workLeft) // 2
    posY := target.workTop + (target.workBottom - target.workTop) // 2

    ; 切入全屏窗口时要先移动光标，再激活窗口。这样浏览器全屏视频不会因
    ; 激活而接管光标；游戏激活后也会在正确的显示器上建立鼠标捕获。
    if (enteringFullscreen) {
        landedIdx := WarpCursor(posX, posY, target, monitors)
        focusReleased := ReleaseLockedForeground(hwnd)
        if (!focusReleased)
            Log("   warning: foreground focus was not released")
        Sleep 80
        if (landedIdx != nextIdx)
            landedIdx := WarpCursor(posX, posY, target, monitors)
        Log("   entered fullscreen target hwnd=" hwnd " title=" WindowTitle(hwnd)
            " cursorMonitor=" landedIdx)
    } else {
        focusReleased := ReleaseLockedForeground(hwnd)
        if (!focusReleased)
            Log("   warning: foreground focus was not released")
        Sleep 80
        landedIdx := WarpCursor(posX, posY, target, monitors)
    }

    if (hwnd) {
        ; 目标窗口已经在前一步激活；若被目标屏幕上的其他程序抢回焦点，再补一次。
        if (!enteringFullscreen) {
            targetFocused := ActivateWindow(hwnd)
            if (!targetFocused) {
                Sleep 120
                targetFocused := ActivateWindow(hwnd)
            }
            if (!targetFocused)
                tipFocusFailed := true
        }
        if (!enteringFullscreen && landedIdx != nextIdx)
            landedIdx := WarpCursor(posX, posY, target, monitors)
    }

    tip := "→ 显示器 " nextIdx "/" monitors.Length
    if (hwnd) {
        tip .= "：" WindowTitle(hwnd)
        if (enteringFullscreen)
            tip .= "（全屏目标）"
        Log("   hwnd=" hwnd " fg=" DllCall("GetForegroundWindow", "Ptr") " title=" WindowTitle(hwnd))
    } else {
        tip .= "（该屏没有可激活窗口）"
        Log("   hwnd=none")
    }
    if (landedIdx != nextIdx)
        tip .= landedIdx ? " · 光标未送达（停在 " landedIdx " 号屏）" : " · 光标未送达（位置未知）"
    if (!focusReleased)
        tip .= " · 未能释放前台焦点"
    if (IsSet(tipFocusFailed))
        tip .= " · 目标窗口未获得焦点"
    ShowTip(tip)
}

; ---------------------------------------------------------------------
;  先切换前台焦点，解除游戏的鼠标捕获。
;  优先激活目标显示器上的窗口；该屏没有普通窗口时，退而激活任务栏。
; ---------------------------------------------------------------------
ReleaseLockedForeground(targetHwnd) {
    previous := DllCall("GetForegroundWindow", "Ptr")
    if (!previous)
        return true

    ; 目标窗口本来就在前台时不需要切换，更不能误落到激活任务栏的分支。
    if (targetHwnd && previous = targetHwnd) {
        Log("   focus already on target: " WindowTitle(targetHwnd))
        return true
    }

    if (targetHwnd) {
        ActivateWindow(targetHwnd)
        Sleep 80
        if (DllCall("GetForegroundWindow", "Ptr") = targetHwnd) {
            Log("   focus released: " WindowTitle(previous) " -> " WindowTitle(targetHwnd))
            return true
        }
    }

    ; 目标屏没有窗口，或者游戏拒绝把焦点交给目标窗口。
    ; 激活任务栏同样会解除游戏的全屏鼠标捕获，但不关闭、最小化游戏。
    taskbar := DllCall("FindWindowW", "Str", "Shell_TrayWnd", "Ptr", 0, "Ptr")
    if (taskbar) {
        ActivateWindow(taskbar)
        Sleep 80
        current := DllCall("GetForegroundWindow", "Ptr")
        if (current != previous) {
            Log("   focus released to taskbar: " WindowTitle(previous))
            return true
        }
    }

    return false
}

; ---------------------------------------------------------------------
;  移动光标；返回光标最终所在的屏号（0 = 不在任何屏上）
; ---------------------------------------------------------------------
WarpCursor(x, y, mon, monitors) {
    pt := Buffer(8, 0)
    Loop 2 {
        DllCall("SetCursorPos", "Int", x, "Int", y)
        Sleep 25
        DllCall("GetCursorPos", "Ptr", pt)
        ax := NumGet(pt, 0, "Int")
        ay := NumGet(pt, 4, "Int")
        idx := MonitorIndexAt(ax, ay, monitors)
        if (idx && monitors[idx].handle = mon.handle)
            return idx
        Sleep 40
    }
    Log(Format("   warp to {1},{2} failed, actual {3},{4} (mon {5})"
        , x, y, ax, ay, idx))
    return idx ? idx : 0
}

MonitorIndexAt(x, y, monitors) {
    for i, m in monitors {
        if (x >= m.left && x < m.right && y >= m.top && y < m.bottom)
            return i
    }
    return 0
}

; ---------------------------------------------------------------------
;  枚举所有显示器（直接用 Win32，和 GetCursorPos/SetCursorPos 同一套坐标系）
;  返回按空间位置排序的数组，每项含 HMONITOR 句柄和物理工作区
; ---------------------------------------------------------------------
GetMonitors() {
    global gMonList
    gMonList := []

    cb := CallbackCreate(EnumMonProc, "Fast", 4)
    DllCall("EnumDisplayMonitors", "Ptr", 0, "Ptr", 0, "Ptr", cb, "Ptr", 0)
    CallbackFree(cb)

    list := gMonList

    ; 插入排序：Left 优先，Top 次之（显示器数量很少）
    Loop list.Length - 1 {
        i := A_Index + 1
        item := list[i]
        j := i - 1
        while (j >= 1 && (list[j].left > item.left
            || (list[j].left = item.left && list[j].top > item.top))) {
            list[j + 1] := list[j]
            j--
        }
        list[j + 1] := item
    }
    return list
}

; ---------------------------------------------------------------------
;  EnumDisplayMonitors 回调：读出 MONITORINFO 的 rcMonitor / rcWork
; ---------------------------------------------------------------------
EnumMonProc(hMon, hdc, lprect, lparam) {
    global gMonList

    mi := Buffer(40, 0)                 ; MONITORINFO
    NumPut("UInt", 40, mi, 0)           ; cbSize
    if (!DllCall("GetMonitorInfoW", "Ptr", hMon, "Ptr", mi))
        return true

    l  := NumGet(mi, 4,  "Int")         ; rcMonitor
    t  := NumGet(mi, 8,  "Int")
    r  := NumGet(mi, 12, "Int")
    b  := NumGet(mi, 16, "Int")
    wl := NumGet(mi, 20, "Int")         ; rcWork
    wt := NumGet(mi, 24, "Int")
    wr := NumGet(mi, 28, "Int")
    wb := NumGet(mi, 32, "Int")

    gMonList.Push({
        handle: hMon,
        left: l, top: t, right: r, bottom: b,
        workLeft: wl, workTop: wt, workRight: wr, workBottom: wb
    })
    return true
}

; ---------------------------------------------------------------------
;  找目标显示器上最靠前的可激活窗口
;  EnumWindows 按 Z 序（从上到下）枚举，取第一个符合条件的就是最上层
; ---------------------------------------------------------------------
FindTopWindowOnMonitor(mon, skipFullscreen := false) {
    global gEnumMon, gEnumFound, gSkipFullscreenTargets, gAllowMinimized
    handle := mon.handle

    ; 第一遍只找可见窗口；找不到再允许最小化窗口（用于把最小化的游戏拉回来）
    Loop 2 {
        gAllowMinimized := (A_Index = 2)
        gEnumMon := handle
        gEnumFound := 0
        gSkipFullscreenTargets := skipFullscreen

        cb := CallbackCreate(EnumWindowProc, "Fast", 2)
        DllCall("EnumWindows", "Ptr", cb, "Ptr", 0)
        CallbackFree(cb)

        if (gEnumFound)
            return gEnumFound
    }
    return 0
}

EnumWindowProc(hwnd, lParam) {
    global gEnumMon, gEnumFound, gSkipFullscreenTargets
    if (gEnumFound)
        return 0                       ; 已找到，停止枚举
    if (!IsCandidateWindow(hwnd))
        return 1
    if (DllCall("MonitorFromWindow", "Ptr", hwnd, "UInt", 2, "Ptr") != gEnumMon)
        return 1

    ; 不要激活独占全屏/无边框全屏游戏。游戏窗口即使是另一台显示器上的
    ; 辅助窗口，激活后也可能让游戏主窗口重新获得焦点并再次锁定鼠标。
    if (gSkipFullscreenTargets && IsFullscreenOnMonitor(hwnd, gEnumMon)) {
        Log("   skip fullscreen hwnd=" hwnd " title=" WindowTitle(hwnd))
        return 1
    }

    gEnumFound := hwnd
    return 0
}

; 判断窗口是否几乎完全覆盖其显示器（全屏，而不是仅最大化到工作区）。
IsFullscreenOnMonitor(hwnd, monitorHandle) {
    rect := Buffer(16, 0)
    if (!DllCall("GetWindowRect", "Ptr", hwnd, "Ptr", rect))
        return false

    winLeft := NumGet(rect, 0, "Int")
    winTop := NumGet(rect, 4, "Int")
    winRight := NumGet(rect, 8, "Int")
    winBottom := NumGet(rect, 12, "Int")

    mi := Buffer(40, 0)
    NumPut("UInt", 40, mi, 0)
    if (!DllCall("GetMonitorInfoW", "Ptr", monitorHandle, "Ptr", mi))
        return false

    monWidth := NumGet(mi, 12, "Int") - NumGet(mi, 4, "Int")
    monHeight := NumGet(mi, 16, "Int") - NumGet(mi, 8, "Int")
    winWidth := winRight - winLeft
    winHeight := winBottom - winTop

    return (monWidth > 0 && monHeight > 0
        && winWidth >= monWidth * 0.98
        && winHeight >= monHeight * 0.98)
}

IsFullscreenWindow(hwnd) {
    if (!hwnd)
        return false
    monitorHandle := DllCall("MonitorFromWindow", "Ptr", hwnd, "UInt", 2, "Ptr")
    return monitorHandle && IsFullscreenOnMonitor(hwnd, monitorHandle)
}

SameProcess(hwndA, hwndB) {
    if (!hwndA || !hwndB)
        return false
    pidA := 0
    pidB := 0
    DllCall("GetWindowThreadProcessId", "Ptr", hwndA, "UInt*", &pidA)
    DllCall("GetWindowThreadProcessId", "Ptr", hwndB, "UInt*", &pidB)
    return pidA && pidA = pidB
}

; ---------------------------------------------------------------------
;  判断一个窗口是否属于“用户眼中的顶层窗口”
; ---------------------------------------------------------------------
IsCandidateWindow(hwnd) {
    global gAllowMinimized

    ; 必须可见，且是顶层窗口
    if (!DllCall("IsWindowVisible", "Ptr", hwnd))
        return false
    if (DllCall("GetAncestor", "Ptr", hwnd, "UInt", 2, "Ptr") != hwnd)  ; GA_ROOT
        return false
    if (DllCall("IsIconic", "Ptr", hwnd) && !gAllowMinimized)           ; 第一遍跳过最小化窗口
        return false

    exStyle := DllCall("GetWindowLongPtrW", "Ptr", hwnd, "Int", -20, "Ptr")
    if (exStyle & 0x00000080)                                           ; WS_EX_TOOLWINDOW
        return false

    ; 有 owner 且没有 WS_EX_APPWINDOW 的窗口不会出现在 Alt+Tab 列表里
    owner := DllCall("GetWindow", "Ptr", hwnd, "UInt", 4, "Ptr")        ; GW_OWNER
    if (owner && !(exStyle & 0x00040000))
        return false

    ; 虚拟桌面 / 后台 UWP 的“隐身”窗口
    cloaked := 0
    if (DllCall("dwmapi\DwmGetWindowAttribute", "Ptr", hwnd, "UInt", 14, "Int*", &cloaked, "UInt", 4) = 0 && cloaked)
        return false

    ; 桌面、任务栏等 shell 窗口
    cls := WindowClassName(hwnd)
    if (cls = "Progman" || cls = "WorkerW"
        || cls = "Shell_TrayWnd" || cls = "Shell_SecondaryTrayWnd")
        return false

    ; 没有标题的多半是辅助窗口
    if (DllCall("GetWindowTextLengthW", "Ptr", hwnd, "Int") = 0)
        return false

    return true
}

; ---------------------------------------------------------------------
;  把窗口切到前台（含绕过 Windows 前台锁的兜底处理）
; ---------------------------------------------------------------------
ActivateWindow(hwnd) {
    if (!hwnd)
        return false

    if (DllCall("IsIconic", "Ptr", hwnd))
        DllCall("ShowWindow", "Ptr", hwnd, "Int", 9)          ; SW_RESTORE

    if (DllCall("GetForegroundWindow", "Ptr") = hwnd)
        return true

    ; 1) 先让 AutoHotkey 自己尝试一次，保持热键线程的前台权限。
    try WinActivate("ahk_id " hwnd)
    Sleep 30
    if (DllCall("GetForegroundWindow", "Ptr") = hwnd)
        return true

    ; 2) 同时附加到前台线程和目标线程，再执行激活与聚焦。
    fg := DllCall("GetForegroundWindow", "Ptr")
    myThread := DllCall("GetCurrentThreadId", "UInt")
    fgThread := fg ? DllCall("GetWindowThreadProcessId", "Ptr", fg, "Ptr", 0, "UInt") : 0
    targetThread := DllCall("GetWindowThreadProcessId", "Ptr", hwnd, "Ptr", 0, "UInt")

    attachedFg := false
    attachedTarget := false
    if (fgThread && fgThread != myThread)
        attachedFg := DllCall("AttachThreadInput", "UInt", myThread, "UInt", fgThread, "Int", true)
    if (targetThread && targetThread != myThread && targetThread != fgThread)
        attachedTarget := DllCall("AttachThreadInput", "UInt", myThread, "UInt", targetThread, "Int", true)

    DllCall("BringWindowToTop", "Ptr", hwnd)
    DllCall("SetForegroundWindow", "Ptr", hwnd)
    DllCall("SetFocus", "Ptr", hwnd)

    if (attachedTarget)
        DllCall("AttachThreadInput", "UInt", myThread, "UInt", targetThread, "Int", false)
    if (attachedFg)
        DllCall("AttachThreadInput", "UInt", myThread, "UInt", fgThread, "Int", false)

    if (DllCall("GetForegroundWindow", "Ptr") = hwnd)
        return true

    ; 3) 仍然被前台锁挡住：用 Alt+Tab 内部使用的 SwitchToThisWindow。
    ;    注意：这里绝不能合成按键（曾用 SendInput 补一个 Alt，会在按住
    ;    Ctrl/Shift 时把修饰键状态弄乱，表现为“按键卡住/一直在触发”）
    try {
        DllCall("SetWindowPos", "Ptr", hwnd, "Ptr", 0
            , "Int", 0, "Int", 0, "Int", 0, "Int", 0x43)       ; TOP + NOSIZE + NOMOVE + SHOW
        DllCall("SwitchToThisWindow", "Ptr", hwnd, "UInt", 1)
    }
    Sleep 120

    ; 4) 管理员兜底：前台全屏游戏仍不肯让位时，直接最小化它
    if (DllCall("GetForegroundWindow", "Ptr") != hwnd && A_IsAdmin) {
        fgNow := DllCall("GetForegroundWindow", "Ptr")
        if (fgNow) {
            DllCall("ShowWindow", "Ptr", fgNow, "Int", 6)   ; SW_MINIMIZE
            Sleep 200
            DllCall("SetForegroundWindow", "Ptr", hwnd)
            try DllCall("SwitchToThisWindow", "Ptr", hwnd, "UInt", 1)
        }
    }

    return DllCall("GetForegroundWindow", "Ptr") = hwnd
}

; ---------------------------------------------------------------------
ShowTip(text) {
    ToolTip(text)
    SetTimer(() => ToolTip(), -1200)
}

; ---------------------------------------------------------------------
;  不抛异常的窗口信息读取（WinGetClass/WinGetTitle 在窗口消失时会抛错）
; ---------------------------------------------------------------------
WindowClassName(hwnd) {
    buf := Buffer(512, 0)
    if (!DllCall("GetClassNameW", "Ptr", hwnd, "Ptr", buf, "Int", 256))
        return ""
    return StrGet(buf, "UTF-16")
}

WindowTitle(hwnd) {
    buf := Buffer(2048, 0)
    DllCall("GetWindowTextW", "Ptr", hwnd, "Ptr", buf, "Int", 1024)
    return StrGet(buf, "UTF-16")
}
