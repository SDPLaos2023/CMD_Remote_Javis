"""
win_arm.py - CLI Entrypoint for Windows UI Automation Engine (win-arm)
Outputs compact JSON for Antigravity and CMD_Remote
"""

import argparse
import json
import sys
from typing import Any, Dict

# Force UTF-8 encoding for stdout
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
                        help="Operation mode")
    parser.add_argument("-TargetTitle", "--target", default=None, help="Target window title (supports substring search)")
    parser.add_argument("-Handle", "--handle", type=int, default=None, help="Window Handle (HWND)")
    parser.add_argument("-ControlName", "--name", default=None, help="Element Name or Label")
    parser.add_argument("-AutoId", "--auto-id", default=None, help="AutomationId of Element")
    parser.add_argument("-ControlType", "--type", default=None, help="Control Type (e.g. Button, Edit, MenuItem)")
    parser.add_argument("-Value", "--value", default="", help="Text value to enter (for SetText mode)")
    parser.add_argument("-Keys", "--keys", default="", help="Hotkey sequence to send (e.g. ^s, %{F4}, {ENTER})")
    parser.add_argument("-AppPath", "--app", default="", help="Application executable path (for Launch mode)")
    parser.add_argument("-Simulate", "--simulate", action="store_true", help="Simulate mouse move/click (default is background invoke)")
    parser.add_argument("-OutputPath", "--output", default=None, help="File path to save screenshot")
    parser.add_argument("-Base64", "--base64", action="store_true", help="Return screenshot image as Base64 in JSON")
    parser.add_argument("-Depth", "--depth", type=int, default=4, help="Control Tree inspection max depth (default 4)")
    parser.add_argument("-Pretty", "--pretty", action="store_true", help="Pretty print JSON output")

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
                result = {"success": False, "error": "Must specify -AppPath to launch application"}
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
                result = {"success": False, "error": "Must specify -Keys for hotkey action"}
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
        result = {"success": False, "error": f"Error during processing: {str(e)}"}

    print_json(result, args.pretty)


def print_json(data: Dict[str, Any], pretty: bool = False):
    """
    Print result as Compact or Formatted JSON to stdout
    """
    if pretty:
        print(json.dumps(data, ensure_ascii=False, indent=2))
    else:
        print(json.dumps(data, ensure_ascii=False, separators=(',', ':')))


if __name__ == "__main__":
    main()
