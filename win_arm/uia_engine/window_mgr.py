"""
window_mgr.py - จัดการหน้าต่างโปรแกรมบน Windows (List, Focus, Launch, Close)
ผสานความแม่นยำระดับ Win32 API เข้ากับ pywinauto UIA Controls
"""

import ctypes
import subprocess
import threading
import time
from typing import List, Dict, Any, Optional
import win32gui
import win32process
from pywinauto import Desktop


def run_on_desktop(fn, *args, **kwargs):
    """
    รันฟังก์ชันใน Worker Thread ที่เชื่อมต่อกับ Active Input Desktop เสมอ
    """
    res = None
    err = None

    def target():
        nonlocal res, err
        try:
            u32 = ctypes.windll.user32
            h_desk = u32.OpenInputDesktop(0, False, 0x01FF)
            if h_desk:
                u32.SetThreadDesktop(h_desk)
            res = fn(*args, **kwargs)
        except Exception as e:
            err = e

    t = threading.Thread(target=target)
    t.start()
    t.join()
    if err:
        raise err
    return res


def _list_windows_impl(filter_text: Optional[str] = None) -> List[Dict[str, Any]]:
    u32 = ctypes.windll.user32
    h_desk = u32.OpenInputDesktop(0, False, 0x01FF)
    windows = []

    def enum_cb(hwnd, _):
        try:
            if not win32gui.IsWindowVisible(hwnd):
                return True
                
            title = win32gui.GetWindowText(hwnd).strip()
            if not title:
                return True
                
            rect = win32gui.GetWindowRect(hwnd)
            width = rect[2] - rect[0]
            height = rect[3] - rect[1]
            if width <= 10 or height <= 10:
                return True

            if filter_text and filter_text.lower() not in title.lower():
                return True

            _, pid = win32process.GetWindowThreadProcessId(hwnd)
            class_name = win32gui.GetClassName(hwnd)

            windows.append({
                "handle": hwnd,
                "title": title,
                "class_name": class_name,
                "pid": pid,
                "rect": [rect[0], rect[1], rect[2], rect[3]],
                "is_active": (hwnd == win32gui.GetForegroundWindow())
            })
        except Exception:
            pass
        return True

    try:
        if h_desk:
            win32gui.EnumDesktopWindows(h_desk, enum_cb, None)
        else:
            win32gui.EnumWindows(enum_cb, None)
    except Exception:
        win32gui.EnumWindows(enum_cb, None)

    return windows


def list_windows(filter_text: Optional[str] = None) -> List[Dict[str, Any]]:
    return run_on_desktop(_list_windows_impl, filter_text=filter_text)


def _find_window_impl(target_title: Optional[str] = None, handle: Optional[int] = None):
    target_hwnd = None

    if handle:
        if win32gui.IsWindow(handle):
            target_hwnd = handle
    elif target_title:
        target_lower = target_title.lower()
        windows = _list_windows_impl()
        for w in windows:
            if target_lower in w["title"].lower():
                target_hwnd = w["handle"]
                break

    if not target_hwnd:
        return None

    # แปลง HWND เป็น pywinauto Window Wrapper
    try:
        d = Desktop(backend="uia")
        return d.window(handle=target_hwnd)
    except Exception:
        try:
            d32 = Desktop(backend="win32")
            return d32.window(handle=target_hwnd)
        except Exception:
            return None


def find_window(target_title: Optional[str] = None, handle: Optional[int] = None):
    return run_on_desktop(_find_window_impl, target_title=target_title, handle=handle)


def _focus_window_impl(target_title: Optional[str] = None, handle: Optional[int] = None) -> Dict[str, Any]:
    win = _find_window_impl(target_title=target_title, handle=handle)
    if not win:
        return {"success": False, "error": f"ไม่พบหน้าต่าง '{target_title or handle}'"}

    try:
        hwnd = win.element_info.handle
        win32gui.ShowWindow(hwnd, 9) # SW_RESTORE
        win32gui.SetForegroundWindow(hwnd)
        try:
            win.set_focus()
        except Exception:
            pass
            
        return {
            "success": True,
            "title": win32gui.GetWindowText(hwnd),
            "handle": hwnd,
            "pid": win.element_info.process_id
        }
    except Exception as e:
        return {"success": False, "error": f"Focus ล้มเหลว: {str(e)}"}


def focus_window(target_title: Optional[str] = None, handle: Optional[int] = None) -> Dict[str, Any]:
    return run_on_desktop(_focus_window_impl, target_title=target_title, handle=handle)


def launch_app(app_path: str, wait_seconds: float = 2.0) -> Dict[str, Any]:
    try:
        proc = subprocess.Popen(app_path, shell=True)
        time.sleep(wait_seconds)

        def check_opened():
            windows = _list_windows_impl()
            for w in windows:
                if w["pid"] == proc.pid:
                    return w["title"], w["handle"]
            return None, None

        title, hwnd = run_on_desktop(check_opened)
        return {
            "success": True,
            "pid": proc.pid,
            "app_path": app_path,
            "window_title": title or "Running",
            "handle": hwnd
        }
    except Exception as e:
        return {"success": False, "error": f"ไม่สามารถเปิดโปรแกรมได้: {str(e)}"}


def _close_window_impl(target_title: Optional[str] = None, handle: Optional[int] = None) -> Dict[str, Any]:
    win = _find_window_impl(target_title=target_title, handle=handle)
    if not win:
        return {"success": False, "error": f"ไม่พบหน้าต่าง '{target_title or handle}'"}

    try:
        hwnd = win.element_info.handle
        title = win32gui.GetWindowText(hwnd)
        win32gui.PostMessage(hwnd, 0x0010, 0, 0) # WM_CLOSE
        return {"success": True, "message": f"ส่งคำสั่งปิดหน้าต่าง '{title}' เรียบร้อยแล้ว"}
    except Exception as e:
        return {"success": False, "error": f"ไม่สามารถปิดหน้าต่างได้: {str(e)}"}


def close_window(target_title: Optional[str] = None, handle: Optional[int] = None) -> Dict[str, Any]:
    return run_on_desktop(_close_window_impl, target_title=target_title, handle=handle)
