#Requires AutoHotkey v2.0
#SingleInstance Force
#MaxThreadsPerHotkey 1
#NoTrayIcon

; =====================================================================
;  将当前窗口移到上一台/下一台显示器
;
;  Ctrl+Alt+M       : 下一台显示器
;  Ctrl+Alt+Right   : 下一台显示器
;  Ctrl+Alt+Left    : 上一台显示器
;
;  显示器按空间位置排序：先横向，后纵向。
;  窗口会居中放到目标显示器的工作区；最大化窗口移动后仍保持最大化。
;  日志：C:\TOOLS\AutoHotKey\switch_monitor.log
; =====================================================================

LogFile := A_ScriptDir "\switch_monitor.log"
gMovingWindow := false
moveKeyState := {next: false, prev: false}
moveHotkeyMap := Map()

OnError((error, mode) => Log(
    "错误 [" mode "] " error.Message " @ " error.What " line " error.Line
))
Log("脚本启动 pid=" ProcessExist())

; 部分 Unity / 反作弊游戏会拦截 AutoHotkey 的键盘钩子。这里直接读取物理按键状态，
; 不注册键盘钩子，因此游戏仍可正常接收输入，同时脚本也能识别组合键。
RegisterRawKeyboard()
RegisterSystemHotkeys()
SetTimer(PollMoveHotkeys, 30)

RegisterRawKeyboard() {
    device := Buffer(16, 0)
    NumPut("UShort", 1, device, 0)          ; HID_USAGE_PAGE_GENERIC
    NumPut("UShort", 6, device, 2)          ; HID_USAGE_GENERIC_KEYBOARD
    NumPut("UInt", 0x100, device, 4)        ; RIDEV_INPUTSINK: receive while game is foreground
    NumPut("Ptr", A_ScriptHwnd, device, 8)

    registered := DllCall("RegisterRawInputDevices"
        , "Ptr", device, "UInt", 1, "UInt", 16)
    if (registered) {
        OnMessage(0x00FF, HandleRawInput)   ; WM_INPUT
    }
    Log("raw keyboard registered=" registered)
}

HandleRawInput(wParam, lParam, msg, hwnd) {
    global moveKeyState, gMovingWindow
    static rawCtrlDown := false
    static rawAltDown := false
    static rawMDown := false
    static rawLeftDown := false
    static rawRightDown := false

    size := 0
    headerSize := 24                     ; sizeof(RAWINPUTHEADER) on 64-bit
    DllCall("GetRawInputData", "Ptr", lParam, "UInt", 0x10000003
        , "Ptr", 0, "UInt*", &size, "UInt", headerSize)
    if (size < headerSize + 16)
        return 0

    data := Buffer(size, 0)
    if (DllCall("GetRawInputData", "Ptr", lParam, "UInt", 0x10000003
        , "Ptr", data, "UInt*", &size, "UInt", headerSize) = 0xFFFFFFFF)
        return 0
    if (NumGet(data, 0, "UInt") != 1)   ; RIM_TYPEKEYBOARD
        return 0

    vk := NumGet(data, headerSize + 6, "UShort")
    message := NumGet(data, headerSize + 8, "UInt")
    isDown := (message = 0x100 || message = 0x104)

    if (vk = 0x11 || vk = 0xA2 || vk = 0xA3) {
        rawCtrlDown := isDown
    } else if (vk = 0x12 || vk = 0xA4 || vk = 0xA5) {
        rawAltDown := isDown
    } else if (vk = 0x4D) {
        if (isDown && !rawMDown && rawCtrlDown && rawAltDown && !gMovingWindow) {
            Log("raw hotkey direction=1")
            MoveToMonitor(1)
        }
        rawMDown := isDown
    } else if (vk = 0x25) {
        if (isDown && !rawLeftDown && rawCtrlDown && rawAltDown && !gMovingWindow) {
            Log("raw hotkey direction=-1")
            MoveToMonitor(-1)
        }
        rawLeftDown := isDown
    } else if (vk = 0x27) {
        if (isDown && !rawRightDown && rawCtrlDown && rawAltDown && !gMovingWindow) {
            Log("raw hotkey direction=1")
            MoveToMonitor(1)
        }
        rawRightDown := isDown
    }
    return 0
}

RegisterSystemHotkeys() {
    global moveHotkeyMap

    ; MOD_NOREPEAT | MOD_CONTROL | MOD_ALT
    modifiers := 0x4003
    definitions := [
        [1, 0x4D, 1],      ; Ctrl+Alt+M
        [2, 0x25, -1],     ; Ctrl+Alt+Left
        [3, 0x27, 1]       ; Ctrl+Alt+Right
    ]

    registered := []
    for definition in definitions {
        if DllCall("RegisterHotKey", "Ptr", A_ScriptHwnd
            , "Int", definition[1], "UInt", modifiers, "UInt", definition[2]) {
            moveHotkeyMap[definition[1]] := definition[3]
            registered.Push(definition[1])
        }
    }
    if (registered.Length) {
        OnMessage(0x0312, HandleMoveHotkey)
        OnExit(CleanupSystemHotkeys)
    }
    Log("system hotkeys registered=" registered.Length)
}

HandleMoveHotkey(wParam, lParam, msg, hwnd) {
    global moveHotkeyMap, gMovingWindow
    if (moveHotkeyMap.Has(wParam) && !gMovingWindow)
        MoveToMonitor(moveHotkeyMap[wParam])
}

CleanupSystemHotkeys(*) {
    global moveHotkeyMap
    for id in moveHotkeyMap {
        DllCall("UnregisterHotKey", "Ptr", A_ScriptHwnd, "Int", id)
    }
    moveHotkeyMap.Clear()
}

PollMoveHotkeys() {
    global moveKeyState, gMovingWindow

    ctrlDown := IsPhysicalKeyDown(0xA2) || IsPhysicalKeyDown(0xA3)
    altDown := IsPhysicalKeyDown(0xA4) || IsPhysicalKeyDown(0xA5)

    nextDown := ctrlDown && altDown && IsPhysicalKeyDown(0x4D)
    prevDown := ctrlDown && altDown && IsPhysicalKeyDown(0x25)

    if (nextDown && !moveKeyState.next) {
        moveKeyState.next := true
        if (!gMovingWindow)
            MoveToMonitor(1)
    } else if (!nextDown) {
        moveKeyState.next := false
    }

    if (prevDown && !moveKeyState.prev) {
        moveKeyState.prev := true
        if (!gMovingWindow)
            MoveToMonitor(-1)
    } else if (!prevDown) {
        moveKeyState.prev := false
    }
}

IsPhysicalKeyDown(virtualKey) {
    return (DllCall("GetAsyncKeyState", "Int", virtualKey, "Short") & 0x8000) != 0
}

MoveWindowToNextMonitor() {
    MoveToMonitor(1)
}

MoveWindowToPrevMonitor() {
    MoveToMonitor(-1)
}

MoveToMonitor(direction) {
    global gMovingWindow
    if (gMovingWindow)
        return
    gMovingWindow := true
    Log("hotkey source=physical-poll direction=" direction)
    try {
        MoveToMonitorCore(direction)
    } finally {
        gMovingWindow := false
    }
}

MoveToMonitorCore(direction) {
    ; 物理像素坐标，避免不同显示器缩放比例导致落点错误。
    try DllCall("SetThreadDpiAwarenessContext", "Ptr", -4)

    hwnd := DllCall("GetForegroundWindow", "Ptr")
    if (!hwnd || !DllCall("IsWindow", "Ptr", hwnd)) {
        ShowTip("没有可移动的前台窗口")
        return
    }

    cls := WindowClassName(hwnd)
    if (cls = "Progman" || cls = "WorkerW" || cls = "Shell_TrayWnd"
        || cls = "Shell_SecondaryTrayWnd") {
        ShowTip("桌面或任务栏不能移动")
        return
    }

    monitors := GetMonitors()
    if (monitors.Length < 2) {
        ShowTip("只检测到 1 台显示器")
        return
    }

    curIdx := MonitorIndexFromWindow(hwnd, monitors)
    nextIdx := curIdx + direction
    if (nextIdx > monitors.Length)
        nextIdx := 1
    if (nextIdx < 1)
        nextIdx := monitors.Length

    source := monitors[curIdx]
    target := monitors[nextIdx]
    wasMaximized := WinGetMinMax(hwnd) = 1
    title := WindowTitle(hwnd)
    processName := WindowProcessName(hwnd)

    Log(Format("hotkey dir={1} hwnd={2} process={3} max={4} cur={5} next={6} title={7}"
        , direction, hwnd, processName, wasMaximized, curIdx, nextIdx, title))
    for i, monitor in monitors
        Log(Format("  mon{1}: {2},{3} {4}x{5} work={6},{7} {8}x{9}"
            , i, monitor.left, monitor.top, monitor.width, monitor.height
            , monitor.workLeft, monitor.workTop, monitor.workWidth, monitor.workHeight))

    ; 部分 Unity / 反作弊游戏使用无边框窗口。保持前台时，输入会被游戏
    ; 接管，窗口位置也可能被游戏重置。先让出前台，移动原窗口句柄，再激活。
    if ((WindowClassName(hwnd) = "UnityWndClass" || IsFullscreenWindow(hwnd))
        && DllCall("GetForegroundWindow", "Ptr") = hwnd) {
        Log("  releasing protected game foreground")
        if (!ReleaseForegroundForMove(hwnd)) {
            ShowTip("当前游戏未能让出前台，移动已取消")
            Log("  failed to release protected game foreground")
            return
        }
    }

    ; 最大化窗口必须临时还原，否则 Windows 可能继续把它最大化到原显示器。
    if (wasMaximized) {
        WinRestore(hwnd)
        Sleep 80
    }

    WinGetPos(&winX, &winY, &winW, &winH, hwnd)
    newW := Min(winW, target.workWidth)
    newH := Min(winH, target.workHeight)
    newX := target.workLeft + (target.workWidth - newW) // 2
    newY := target.workTop + (target.workHeight - newH) // 2

    WinMove(newX, newY, newW, newH, hwnd)
    Sleep 120

    landedIdx := MonitorIndexFromWindow(hwnd, monitors)
    if (landedIdx != nextIdx) {
        ; 某些不同 DPI 的窗口会拒绝第一次 WinMove，用 SetWindowPos 再强制一次。
        Log(Format("  retry SetWindowPos target={1},{2} {3}x{4}"
            , newX, newY, newW, newH))
        DllCall("SetWindowPos", "Ptr", hwnd, "Ptr", 0
            , "Int", newX, "Int", newY, "Int", newW, "Int", newH
            , "UInt", 0x0014)                                   ; NOZORDER + NOACTIVATE
        Sleep 120
        landedIdx := MonitorIndexFromWindow(hwnd, monitors)
    }

    ; Unity 无边框窗口有时会在第一帧后重新应用自己的位置，再等待并校正一次。
    Sleep 180
    landedIdx := MonitorIndexFromWindow(hwnd, monitors)
    if (landedIdx != nextIdx) {
        Log(Format("  late retry SetWindowPos target={1},{2} {3}x{4}"
            , newX, newY, newW, newH))
        DllCall("SetWindowPos", "Ptr", hwnd, "Ptr", 0
            , "Int", newX, "Int", newY, "Int", newW, "Int", newH
            , "UInt", 0x0014)
        Sleep 180
        landedIdx := MonitorIndexFromWindow(hwnd, monitors)
    }

    if (wasMaximized) {
        WinMaximize(hwnd)
        Sleep 80
    }

    ActivateWindow(hwnd)
    Sleep 50

    if (landedIdx = nextIdx) {
        ShowTip("→ 显示器 " nextIdx "/" monitors.Length)
        Log(Format("  moved successfully target={1} actual={2} max={3}"
            , nextIdx, landedIdx, WinGetMinMax(hwnd) = 1))
    } else {
        ShowTip("移动失败：窗口仍在显示器 " landedIdx)
        Log(Format("  move failed target={1} actual={2}", nextIdx, landedIdx))
    }
}

ReleaseForegroundForMove(hwnd) {
    ; 等待物理键松开后再发送 Alt+Tab，避免组合键叠在一起造成修饰键残留。
    WaitPhysicalKeysReleased([0xA2, 0xA3, 0xA4, 0xA5, 0x4D, 0x25, 0x27], 1200)
    Sleep 40
    SendInput("{Blind}{Alt down}{Tab}{Alt up}")
    Sleep 320

    if (DllCall("GetForegroundWindow", "Ptr") != hwnd) {
        Log("  game foreground released via Alt+Tab")
        return true
    }

    ; Alt+Tab 被游戏拦截时，用任务栏强制解除前台，再移动窗口。
    taskbar := DllCall("FindWindowW", "Str", "Shell_TrayWnd", "Ptr", 0, "Ptr")
    if (taskbar) {
        ActivateWindow(taskbar)
        Sleep 160
    }
    return DllCall("GetForegroundWindow", "Ptr") != hwnd
}

WaitPhysicalKeysReleased(virtualKeys, timeoutMs) {
    deadline := A_TickCount + timeoutMs
    loop {
        anyDown := false
        for vk in virtualKeys {
            if (IsPhysicalKeyDown(vk)) {
                anyDown := true
                break
            }
        }
        if (!anyDown || A_TickCount >= deadline)
            return !anyDown
        Sleep 20
    }
}

GetMonitors() {
    global gMonitorList
    gMonitorList := []

    callback := CallbackCreate(EnumMonitorProc, "Fast", 4)
    DllCall("EnumDisplayMonitors", "Ptr", 0, "Ptr", 0, "Ptr", callback, "Ptr", 0)
    CallbackFree(callback)

    monitors := gMonitorList
    Loop monitors.Length - 1 {
        i := A_Index + 1
        item := monitors[i]
        j := i - 1
        while (j >= 1
            && (monitors[j].left > item.left
                || (monitors[j].left = item.left && monitors[j].top > item.top))) {
            monitors[j + 1] := monitors[j]
            j--
        }
        monitors[j + 1] := item
    }
    return monitors
}

EnumMonitorProc(hMonitor, hdc, rect, data) {
    global gMonitorList

    info := Buffer(40, 0)
    NumPut("UInt", 40, info, 0)
    if (!DllCall("GetMonitorInfoW", "Ptr", hMonitor, "Ptr", info))
        return true

    left := NumGet(info, 4, "Int")
    top := NumGet(info, 8, "Int")
    right := NumGet(info, 12, "Int")
    bottom := NumGet(info, 16, "Int")
    workLeft := NumGet(info, 20, "Int")
    workTop := NumGet(info, 24, "Int")
    workRight := NumGet(info, 28, "Int")
    workBottom := NumGet(info, 32, "Int")

    gMonitorList.Push({
        handle: hMonitor,
        left: left,
        top: top,
        right: right,
        bottom: bottom,
        width: right - left,
        height: bottom - top,
        workLeft: workLeft,
        workTop: workTop,
        workRight: workRight,
        workBottom: workBottom,
        workWidth: workRight - workLeft,
        workHeight: workBottom - workTop
    })
    return true
}

MonitorIndexFromWindow(hwnd, monitors) {
    monitorHandle := DllCall("MonitorFromWindow", "Ptr", hwnd, "UInt", 2, "Ptr")
    for i, monitor in monitors {
        if (monitor.handle = monitorHandle)
            return i
    }

    ; 兜底：使用窗口中心点判断。
    rect := Buffer(16, 0)
    if (DllCall("GetWindowRect", "Ptr", hwnd, "Ptr", rect)) {
        x := (NumGet(rect, 0, "Int") + NumGet(rect, 8, "Int")) // 2
        y := (NumGet(rect, 4, "Int") + NumGet(rect, 12, "Int")) // 2
        for i, monitor in monitors {
            if (x >= monitor.left && x < monitor.right
                && y >= monitor.top && y < monitor.bottom)
                return i
        }
    }
    return 1
}

ShowTip(text) {
    ToolTip(text)
    SetTimer(() => ToolTip(), -1200)
}

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

WindowProcessName(hwnd) {
    try {
        pid := WinGetPID("ahk_id " hwnd)
        return ProcessGetName(pid)
    } catch {
        return ""
    }
}

IsFullscreenWindow(hwnd) {
    if (!hwnd)
        return false

    monitorHandle := DllCall("MonitorFromWindow", "Ptr", hwnd, "UInt", 2, "Ptr")
    if (!monitorHandle)
        return false

    mi := Buffer(40, 0)
    NumPut("UInt", 40, mi, 0)
    if (!DllCall("GetMonitorInfoW", "Ptr", monitorHandle, "Ptr", mi))
        return false

    rect := Buffer(16, 0)
    if (!DllCall("GetWindowRect", "Ptr", hwnd, "Ptr", rect))
        return false

    monWidth := NumGet(mi, 12, "Int") - NumGet(mi, 4, "Int")
    monHeight := NumGet(mi, 16, "Int") - NumGet(mi, 8, "Int")
    winWidth := NumGet(rect, 8, "Int") - NumGet(rect, 0, "Int")
    winHeight := NumGet(rect, 12, "Int") - NumGet(rect, 4, "Int")
    return monWidth > 0 && monHeight > 0
        && winWidth >= monWidth * 0.98 && winHeight >= monHeight * 0.98
}

ActivateWindow(hwnd) {
    if (!hwnd)
        return false

    if (DllCall("IsIconic", "Ptr", hwnd))
        DllCall("ShowWindow", "Ptr", hwnd, "Int", 9)   ; SW_RESTORE
    if (DllCall("GetForegroundWindow", "Ptr") = hwnd)
        return true

    try WinActivate("ahk_id " hwnd)
    Sleep 40
    if (DllCall("GetForegroundWindow", "Ptr") = hwnd)
        return true

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

    try DllCall("SwitchToThisWindow", "Ptr", hwnd, "UInt", 1)
    Sleep 100
    return DllCall("GetForegroundWindow", "Ptr") = hwnd
}

Log(text) {
    global LogFile
    try FileAppend(FormatTime(, "yyyy-MM-dd HH:mm:ss") "  " text "`n", LogFile, "UTF-8")
}
