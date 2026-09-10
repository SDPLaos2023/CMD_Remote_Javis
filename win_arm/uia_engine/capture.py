"""
capture.py - จับภาพหน้าต่างเป้าหมายหรือทั้งหน้าจอ เซฟเป็น PNG และแปลง Base64
"""

import base64
import io
import os
import time
from typing import Dict, Any, Optional
from PIL import ImageGrab
from .window_mgr import run_on_desktop, _find_window_impl


def _capture_impl(target_title: Optional[str] = None, handle: Optional[int] = None,
                  output_path: Optional[str] = None, as_base64: bool = False) -> Dict[str, Any]:
    img = None
    target_name = "Desktop"

    if target_title or handle:
        win = _find_window_impl(target_title=target_title, handle=handle)
        if win:
            target_name = win.window_text() or "Window"
            try:
                img = win.capture_as_image()
            except Exception:
                pass

    if img is None:
        img = ImageGrab.grab(all_screens=True)

    if not output_path:
        ts = int(time.time())
        folder = os.path.join(os.getcwd(), "screenshots")
        os.makedirs(folder, exist_ok=True)
        output_path = os.path.join(folder, f"snap_{ts}.png")

    os.makedirs(os.path.dirname(os.path.abspath(output_path)), exist_ok=True)
    img.save(output_path, "PNG")

    result = {
        "success": True,
        "target": target_name,
        "file_path": os.path.abspath(output_path),
        "size": {"width": img.width, "height": img.height}
    }

    if as_base64:
        buf = io.BytesIO()
        img.save(buf, format="PNG")
        result["base64"] = base64.b64encode(buf.getvalue()).decode("utf-8")

    return result


def capture_window(target_title: Optional[str] = None, handle: Optional[int] = None,
                   output_path: Optional[str] = None, as_base64: bool = False) -> Dict[str, Any]:
    return run_on_desktop(_capture_impl, target_title=target_title, handle=handle,
                          output_path=output_path, as_base64=as_base64)
