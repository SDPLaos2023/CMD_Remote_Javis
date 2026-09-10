"""
win_arm.py - CLI Entrypoint หลักสำหรับ Windows UI Automation Engine (win-arm)
ส่งออกผลลัพธ์เป็น Compact JSON สำหรับ Antigravity และ CMD_Remote
"""

import argparse
import json
import sys
from typing import Any, Dict

# บังคับ encoding เป็น UTF-8 สำหรับ stdout เพื่อรองรับภาษาไทย 100%
if sys.stdout.encoding != 'utf-8':
    try:
        sys.stdout.reconfigure(encoding='utf-8')
    except Exception:
        pass

from uia_engine.window_mgr import list_windows, focus_window, launch_app, close_window
from uia_engine.inspector import inspect_controls
from uia_engine.controller import click_element, set_element_text, send_hotkey
from uia_engine.capture import capture_window


def main():
    parser = argparse.ArgumentParser(description="win-arm: Windows UI Automation Engine for Antigravity & CMD_Remote")
    parser.add_argument("-Mode", "--mode", required=True, 
                        choices=["ListWindows", "Inspect", "Click", "SetText", "Hotkey", "Screenshot", "Launch", "Close", "Focus"],
                        help="โหมดการทำงาน")
    parser.add_argument("-TargetTitle", "--target", default=None, help="ชื่อหน้าต่างเป้าหมาย (รองรับค้นหาบางส่วน)")
    parser.add_argument("-Handle", "--handle", type=int, default=None, help="Window Handle (HWND)")
    parser.add_argument("-ControlName", "--name", default=None, help="ชื่อหรือป้ายกำกับของปุ่ม/กล่องข้อความ")
    parser.add_argument("-AutoId", "--auto-id", default=None, help="AutomationId ของ Element")
    parser.add_argument("-ControlType", "--type", default=None, help="ประเภท Control เช่น Button, Edit, MenuItem")
    parser.add_argument("-Value", "--value", default="", help="ข้อความที่ต้องการกรอก (สำหรับโหมด SetText)")
    parser.add_argument("-Keys", "--keys", default="", help="คีย์ลัดที่ต้องการส่ง (เช่น ^s, %{F4}, {ENTER})")
    parser.add_argument("-AppPath", "--app", default="", help="Path ของโปรแกรมที่ต้องการเปิด (สำหรับโหมด Launch)")
    parser.add_argument("-Simulate", "--simulate", action="store_true", help="เลื่อนเมาส์ไปคลิกจริง (ค่าเริ่มต้นคือ Background Invoke ไม่แย่งเมาส์)")
    parser.add_argument("-OutputPath", "--output", default=None, help="Path สำหรับบันทึกภาพหน้าจอ")
    parser.add_argument("-Base64", "--base64", action="store_true", help="แปลงรูปภาพเป็น Base64 ส่งกลับมาใน JSON")
    parser.add_argument("-Depth", "--depth", type=int, default=4, help="ความลึกในการสแกน Control Tree (ค่าเริ่มต้น 4)")
    parser.add_argument("-Pretty", "--pretty", action="store_true", help="จัดรูปแบบ JSON ให้อ่านง่าย")

    args = parser.parse_args()
    result: Dict[str, Any] = {"success": False}

    try:
        if args.mode == "ListWindows":
            windows = list_windows(filter_text=args.target)
            result = {
                "success": True,
                "count": len(windows),
                "windows": windows
            }

        elif args.mode == "Launch":
            if not args.app:
                result = {"success": False, "error": "ต้องระบุ -AppPath สำหรับการเปิดโปรแกรม"}
            else:
                result = launch_app(args.app)

        elif args.mode == "Focus":
            result = focus_window(target_title=args.target, handle=args.handle)

        elif args.mode == "Close":
            result = close_window(target_title=args.target, handle=args.handle)

        elif args.mode == "Inspect":
            result = inspect_controls(target_title=args.target, handle=args.handle, max_depth=args.depth)

        elif args.mode == "Click":
            result = click_element(
                target_title=args.target,
                handle=args.handle,
                name=args.name,
                auto_id=args.auto_id,
                control_type=args.type,
                simulate_move=args.simulate
            )

        elif args.mode == "SetText":
            result = set_element_text(
                target_title=args.target,
                handle=args.handle,
                value=args.value,
                name=args.name,
                auto_id=args.auto_id
            )

        elif args.mode == "Hotkey":
            if not args.keys:
                result = {"success": False, "error": "ต้องระบุ -Keys สำหรับการส่งคีย์ลัด"}
            else:
                result = send_hotkey(target_title=args.target, handle=args.handle, keys=args.keys)

        elif args.mode == "Screenshot":
            result = capture_window(
                target_title=args.target,
                handle=args.handle,
                output_path=args.output,
                as_base64=args.base64
            )

    except Exception as e:
        result = {"success": False, "error": f"เกิดข้อผิดพลาดในการประมวลผล: {str(e)}"}

    print_json(result, args.pretty)


def print_json(data: Dict[str, Any], pretty: bool = False):
    """
    พิมพ์ผลลัพธ์เป็น Compact JSON หรือ Formatted JSON ออกทาง stdout
    """
    if pretty:
        print(json.dumps(data, ensure_ascii=False, indent=2))
    else:
        print(json.dumps(data, ensure_ascii=False, separators=(',', ':')))


if __name__ == "__main__":
    main()
