"""
controller.py - สั่งการควบคุม UI Elements (Click, SetText, Hotkey)
"""

from typing import Dict, Any, Optional
from .window_mgr import run_on_desktop, _find_window_impl


def _find_control(win, name: Optional[str] = None, auto_id: Optional[str] = None, control_type: Optional[str] = None):
    descendants = win.descendants()
    for c in descendants:
        try:
            elem = c.element_info
            if auto_id and elem.automation_id == auto_id:
                return c
            if name:
                text = c.window_text().strip()
                if name.lower() == text.lower() or name.lower() in text.lower():
                    if control_type:
                        if control_type.lower() in (elem.control_type or "").lower():
                            return c
                    else:
                        return c
            if control_type and not name and not auto_id:
                if control_type.lower() in (elem.control_type or "").lower():
                    return c
        except Exception:
            continue
    return None


def _click_impl(target_title: Optional[str] = None, handle: Optional[int] = None,
                name: Optional[str] = None, auto_id: Optional[str] = None,
                control_type: Optional[str] = None, simulate_move: bool = False) -> Dict[str, Any]:
    win = _find_window_impl(target_title=target_title, handle=handle)
    if not win:
        return {"success": False, "error": f"ไม่พบหน้าต่าง '{target_title or handle}'"}

    ctrl = _find_control(win, name=name, auto_id=auto_id, control_type=control_type)
    if not ctrl:
        return {"success": False, "error": f"ไม่พบ Control ที่ตรงกับ Name='{name}', AutoId='{auto_id}'"}

    ctrl_name = ctrl.window_text() or auto_id or "Element"
    try:
        if not simulate_move:
            try:
                ctrl.invoke()
                return {"success": True, "action": "invoke", "name": ctrl_name, "mode": "background"}
            except Exception:
                pass

        ctrl.click_input()
        return {"success": True, "action": "click", "name": ctrl_name, "mode": "simulated"}
    except Exception as e:
        return {"success": False, "error": f"คลิกล้มเหลว: {str(e)}"}


def click_element(target_title: Optional[str] = None, handle: Optional[int] = None,
                  name: Optional[str] = None, auto_id: Optional[str] = None,
                  control_type: Optional[str] = None, simulate_move: bool = False) -> Dict[str, Any]:
    return run_on_desktop(_click_impl, target_title=target_title, handle=handle,
                          name=name, auto_id=auto_id, control_type=control_type, simulate_move=simulate_move)


def _set_text_impl(target_title: Optional[str] = None, handle: Optional[int] = None,
                   value: str = "", name: Optional[str] = None, auto_id: Optional[str] = None) -> Dict[str, Any]:
    win = _find_window_impl(target_title=target_title, handle=handle)
    if not win:
        return {"success": False, "error": f"ไม่พบหน้าต่าง '{target_title or handle}'"}

    ctrl = None
    if name or auto_id:
        ctrl = _find_control(win, name=name, auto_id=auto_id, control_type="Edit")
        
    # หากไม่พบ หรือไม่ได้ระบุชื่อ ให้เลือก Edit control ตัวแรก
    if not ctrl:
        ctrl = _find_control(win, control_type="Edit")
        
    # หากยังไม่พบ ลอง Document control
    if not ctrl:
        ctrl = _find_control(win, control_type="Document")

    if not ctrl:
        return {"success": False, "error": f"ไม่พบช่องกรอกข้อความ (Edit) ในหน้าต่าง '{win.window_text()}'"}

    ctrl_name = ctrl.window_text() or auto_id or "TextBox"
    try:
        try:
            ctrl.set_edit_text(value)
            return {"success": True, "name": ctrl_name, "value_length": len(value), "method": "set_edit_text"}
        except Exception:
            pass

        ctrl.set_focus()
        ctrl.type_keys("^a{BACKSPACE}", with_spaces=True)
        ctrl.type_keys(value, with_spaces=True)
        return {"success": True, "name": ctrl_name, "value_length": len(value), "method": "type_keys"}
    except Exception as e:
        return {"success": False, "error": f"กรอกข้อความล้มเหลว: {str(e)}"}


def set_element_text(target_title: Optional[str] = None, handle: Optional[int] = None,
                     value: str = "", name: Optional[str] = None, auto_id: Optional[str] = None) -> Dict[str, Any]:
    return run_on_desktop(_set_text_impl, target_title=target_title, handle=handle,
                          value=value, name=name, auto_id=auto_id)


def _hotkey_impl(target_title: Optional[str] = None, handle: Optional[int] = None, keys: str = "") -> Dict[str, Any]:
    win = _find_window_impl(target_title=target_title, handle=handle)
    if not win:
        return {"success": False, "error": f"ไม่พบหน้าต่าง '{target_title or handle}'"}

    try:
        win.set_focus()
        win.type_keys(keys)
        return {"success": True, "keys": keys, "target_window": win.window_text()}
    except Exception as e:
        return {"success": False, "error": f"ส่งคีย์ลัดล้มเหลว: {str(e)}"}


def send_hotkey(target_title: Optional[str] = None, handle: Optional[int] = None, keys: str = "") -> Dict[str, Any]:
    return run_on_desktop(_hotkey_impl, target_title=target_title, handle=handle, keys=keys)
