"""
inspector.py - สแกน UI Controls ในหน้าต่างและจัดโครงสร้างเป็น Compact JSON
"""

from typing import List, Dict, Any, Optional
from .window_mgr import run_on_desktop, find_window


INTERACTIVE_TYPES = {
    "Button", "Edit", "ComboBox", "CheckBox", "RadioButton", 
    "MenuItem", "TabItem", "Hyperlink", "Text", "ListItem", 
    "TreeItem", "ToolBar", "Document", "SplitButton", "ScrollBar"
}


def _inspect_impl(target_title: Optional[str] = None, handle: Optional[int] = None, max_depth: int = 4) -> Dict[str, Any]:
    from .window_mgr import _find_window_impl
    win = _find_window_impl(target_title=target_title, handle=handle)
    if not win:
        return {"success": False, "error": f"ไม่พบหน้าต่าง '{target_title or handle}'"}

    controls = []
    try:
        descendants = win.descendants()
        for c in descendants:
            try:
                elem = c.element_info
                ctype = elem.control_type
                name = c.window_text().strip()
                auto_id = elem.automation_id or ""
                rect = c.rectangle()

                # กรองเฉพาะ Element ที่มีขนาดและมีชื่อ/ID หรือเป็น Interactive Type
                if (ctype in INTERACTIVE_TYPES or name or auto_id) and rect.width() > 0 and rect.height() > 0:
                    item = {
                        "type": ctype,
                        "name": name,
                        "auto_id": auto_id,
                        "rect": [rect.left, rect.top, rect.right, rect.bottom]
                    }
                    controls.append(item)
            except Exception:
                continue

        return {
            "success": True,
            "target_window": win.window_text(),
            "count": len(controls),
            "controls": controls[:150] # จำกัดไม่เกิน 150 elements เพื่อประหยัด token
        }
    except Exception as e:
        return {"success": False, "error": f"เกิดข้อผิดพลาดในการสแกน Controls: {str(e)}"}


def inspect_controls(target_title: Optional[str] = None, handle: Optional[int] = None, max_depth: int = 4) -> Dict[str, Any]:
    return run_on_desktop(_inspect_impl, target_title=target_title, handle=handle, max_depth=max_depth)
