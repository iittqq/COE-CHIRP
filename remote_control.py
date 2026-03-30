import asyncio
import subprocess
import json
import random
from websockets import connect, ConnectionClosed
import uiautomator2 as u2
import gzip
import base64
from io import BytesIO
import traceback

SERVER_URL = (
    "wss://ywh1uzhhk9.execute-api.us-east-2.amazonaws.com/test?deviceId=testAndroid"
)
APP = "eu.deeper.fishdeeper"


def capture_ui_state_zipped():

    try:
        d = u2.connect()
        xml = d.dump_hierarchy()

        buf = BytesIO()
        with gzip.GzipFile(fileobj=buf, mode="wb") as f:
            f.write(xml.encode("utf-8"))

        compressed_b64 = base64.b64encode(buf.getvalue()).decode("utf-8")
        return True, compressed_b64
    except Exception as e:
        return False, str(e)


def run_as_root(command: str):
    process = subprocess.Popen(
        ["su"],
        stdin=subprocess.PIPE,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
    )
    stdout, stderr = process.communicate(command + "\n")
    print("stdout:", stdout.strip())
    print("stderr:", stderr.strip())


async def handle_command(ws, command):
    try:
        data = json.loads(command)

        if data.get("message") in ("Forbidden", "forbidden"):
            return

        if isinstance(data.get("body"), str):
            try:
                data = json.loads(data["body"])
            except json.JSONDecodeError:
                pass

        cmd_type = data.get("action") or data.get("type")
        response = {"action": cmd_type, "status": "ok"}
        response["target"] = data.get("sender", None)

        # Execute commands
        if cmd_type == "tap":
            x, y = data.get("x"), data.get("y")
            if x is not None and y is not None:
                run_as_root(f"input tap {x} {y}")
                print(f"Executed: tap {x} {y}")

        elif cmd_type == "swipe":
            x1, y1, x2, y2 = (
                data.get("x1"),
                data.get("y1"),
                data.get("x2"),
                data.get("y2"),
            )
            duration = data.get("duration", 300)
            run_as_root(f"input swipe {x1} {y1} {x2} {y2} {duration}")
            print(f"Executed: swipe from ({x1},{y1}) to ({x2},{y2})")

        elif cmd_type == "launch":
            package = data.get("package")
            if package:
                run_as_root(f"am start -n {package}")
                print(f"Launched package: {package}")

        elif cmd_type == "restart":
            package = data.get("package") or "eu.deeper.fishdeeper"
            activity = (
                data.get("activity") or "eu.deeper.app.scan.live.MainScreenActivity"
            )
            run_as_root(f"am force-stop {package}")
            await asyncio.sleep(1.0)
            run_as_root(f"am start -n {package}/{activity}")
            print(f"Restarted: {package}/{activity}")

        elif cmd_type == "ping":
            response["status"] = "pong"

        elif cmd_type == "clickText":
            txt = data.get("text")
            if not txt:
                response["status"] = "error"
                response["error"] = "Missing text field"
            else:
                try:
                    d = u2.connect()
                    print(f"Searching for text: '{txt}'")

                    clicked = False

                    node = d(text=txt)
                    if node.exists:
                        info = node.info
                        if info.get("clickable"):
                            node.click()
                            print(f"Clicked directly on clickable text: {txt}")
                            clicked = True
                        else:
                            parent = d.xpath(
                                f"//*[@text='{txt}']/ancestor::*[@clickable='true']"
                            )
                            parents = parent.all()
                            if parents:
                                parents[0].click()
                                print(f"Clicked clickable ancestor for exact '{txt}'")
                                clicked = True
                            else:
                                node.click_exists(timeout=3.0)
                                print(f"Fallback clicked node for '{txt}'")
                                clicked = True

                    if not clicked:
                        for obj in d.xpath(f"//*[contains(@text,'{txt}')]").all():
                            info = obj.info
                            if info.get("clickable"):
                                obj.click()
                                print(f"Clicked clickable element containing '{txt}'")
                                clicked = True
                                break
                            else:
                                parent = d.xpath(
                                    f"//*[contains(@text,'{txt}')]/ancestor::*[@clickable='true']"
                                )
                                parents = parent.all()
                                if parents:
                                    parents[0].click()
                                    print(
                                        f"Clicked clickable ancestor for partial '{txt}'"
                                    )
                                    clicked = True
                                    break

                    if not clicked:
                        print(f"No clickable node or ancestor found for '{txt}'")

                    response["status"] = "clicked" if clicked else "not_found"

                except Exception as e:
                    print(f"Error in clickText: {e}")
                    traceback.print_exc()
                    response["status"] = "error"
                    response["error"] = str(e)

        elif cmd_type == "clickById":
            rid = data.get("resourceId")
            if not rid:
                response["status"] = "error"
                response["error"] = "Missing resourceId field"
            else:
                try:
                    import xml.etree.ElementTree as ET, re

                    d = u2.connect()
                    print(f"Searching XML for resource-id='{rid}' and nearby Button")

                    xml_str = d.dump_hierarchy()
                    root = ET.fromstring(xml_str)
                    all_nodes = list(root.iter("node"))

                    def parse_bounds(b):
                        m = re.match(r"\[(\d+),(\d+)\]\[(\d+),(\d+)\]", b)
                        if not m:
                            return None
                        x1, y1, x2, y2 = map(int, m.groups())
                        return (x1 + x2) // 2, (y1 + y2) // 2

                    target_index = None
                    for i, node in enumerate(all_nodes):
                        if node.attrib.get("resource-id", "") == rid:
                            target_index = i
                            break

                    if target_index is None:
                        print(f"No node found with resource-id='{rid}'")
                        response["status"] = "not_found"
                    else:
                        button_bounds = None

                        for j in range(target_index - 1, -1, -1):
                            cls = all_nodes[j].attrib.get("class", "")
                            if "Button" in cls:
                                button_bounds = all_nodes[j].attrib.get("bounds")
                                print(
                                    f"Found preceding Button for '{rid}': {button_bounds}"
                                )
                                break

                        if not button_bounds:
                            for j in range(target_index + 1, len(all_nodes)):
                                cls = all_nodes[j].attrib.get("class", "")
                                if "Button" in cls:
                                    button_bounds = all_nodes[j].attrib.get("bounds")
                                    print(
                                        f"Found following Button for '{rid}': {button_bounds}"
                                    )
                                    break

                        if not button_bounds:
                            print(
                                "No Button class found — trying clickable node near target"
                            )
                            for j in range(
                                max(0, target_index - 5),
                                min(len(all_nodes), target_index + 5),
                            ):
                                clickable = (
                                    all_nodes[j].attrib.get("clickable") == "true"
                                )
                                b = all_nodes[j].attrib.get("bounds")
                                if clickable and b:
                                    button_bounds = b
                                    print(f"Found clickable neighbor: {b}")
                                    break

                        if button_bounds:
                            xy = parse_bounds(button_bounds)
                            if xy:
                                cx, cy = xy
                                run_as_root(f"input tap {cx} {cy}")
                                print(f"Tapped at ({cx}, {cy}) for '{rid}'")
                                response["status"] = "clicked_button"
                            else:
                                print(f"Invalid bounds format for {button_bounds}")
                                response["status"] = "bad_bounds"
                        else:
                            print(f"No clickable element found near '{rid}'")
                            response["status"] = "no_button"

                except Exception as e:
                    print(f"Error in clickById: {e}")
                    traceback.print_exc()
                    response["status"] = "error"
                    response["error"] = str(e)

        elif cmd_type == "clickTextDirect":
            txt = data.get("text")
            if not txt:
                response["status"] = "error"
                response["error"] = "Missing text field"
            else:
                try:
                    import xml.etree.ElementTree as ET, re

                    d = u2.connect()
                    print(f"Clicking directly on text node '{txt}'")

                    xml_str = d.dump_hierarchy()
                    root = ET.fromstring(xml_str)
                    all_nodes = list(root.iter("node"))

                    target_bounds = None
                    for node in all_nodes:
                        if node.attrib.get("text") == txt:
                            target_bounds = node.attrib.get("bounds")
                            break

                    if target_bounds:
                        m = re.match(r"\[(\d+),(\d+)\]\[(\d+),(\d+)\]", target_bounds)
                        if m:
                            x1, y1, x2, y2 = map(int, m.groups())
                            cx, cy = (x1 + x2) // 2, (y1 + y2) // 2
                            run_as_root(f"input tap {cx} {cy}")
                            print(f"Tapped directly at ({cx},{cy}) for '{txt}'")
                            response["status"] = "clicked_direct_text"
                        else:
                            response["status"] = "bad_bounds"
                    else:
                        print(f"No node found with text='{txt}'")
                        response["status"] = "not_found"

                    # return updated UI
                    await asyncio.sleep(2)
                    ok, xml_zip = capture_ui_state_zipped()
                    if ok:
                        response["ui_state_zip_b64"] = xml_zip

                except Exception as e:
                    print(f"Error in clickTextDirect: {e}")
                    traceback.print_exc()
                    response["status"] = "error"
                    response["error"] = str(e)
        elif cmd_type == "clickByDescription":
            desc = data.get("description")
            if not desc:
                response["status"] = "error"
                response["error"] = "Missing description field"
            else:
                try:
                    d = u2.connect()
                    print(f"Searching for content-desc: '{desc}'")

                    node = d(description=desc)
                    if not node.exists:
                        node = d(text=desc)

                    clicked = False
                    if node.exists:
                        info = node.info
                        if info.get("clickable"):
                            node.click()
                            print(
                                f"Clicked directly on clickable description element: {desc}"
                            )
                            clicked = True
                        else:
                            xpath_query = f"//*[@content-desc='{desc}']/ancestor::*[@clickable='true']"
                            if not clicked:
                                xpath_query = f"//*[@text='{desc}']/ancestor::*[@clickable='true']"

                            parent = d.xpath(xpath_query)
                            parents = parent.all()
                            if parents:
                                parents[0].click()
                                print(f"Clicked clickable ancestor for '{desc}'")
                                clicked = True
                            else:
                                node.click_exists(timeout=3.0)
                                print(f"Fallback clicked node bounds for '{desc}'")
                                clicked = True

                    response["status"] = "clicked" if clicked else "not_found"

                except Exception as e:
                    print(f"Error in clickByDescription: {e}")
                    traceback.print_exc()
                    response["status"] = "error"
                    response["error"] = str(e)

        await asyncio.sleep(10.0)

        ok, data = capture_ui_state_zipped()
        if ok:
            response["ui_state_zip_b64"] = data
        else:
            response["error"] = data

        await ws.send(json.dumps(response))

    except Exception as e:
        print("Error:", e)
        await ws.send(json.dumps({"error": str(e)}))


async def listen():
    try:
        async with connect(
            SERVER_URL,
            ping_interval=None,  # disable protocol-level ping for now
            ping_timeout=None,
            close_timeout=5,
            max_size=2**20,
        ) as ws:
            print("Connected:", SERVER_URL)

            async def receiver():
                while True:
                    try:
                        msg = await ws.recv()
                        print("Raw message:", msg)
                        await handle_command(ws, msg)
                    except ConnectionClosed as cc:
                        print(
                            f"[receiver] Connection closed: code={cc.code} reason={cc.reason}"
                        )
                        raise
                    except Exception as e:
                        print(
                            "[receiver] Exception while receiving or handling message:"
                        )
                        traceback.print_exc()
                        break  # optional: stop loop on error

            await receiver()

    except Exception as e:
        print("[listen] Exception caught:")
        traceback.print_exc()
        raise


async def persistent_listener():
    backoff = 1
    while True:
        try:
            await listen()
            backoff = 1
        except ConnectionClosed as cc:
            print(f"Closed: code={cc.code} reason={cc.reason}")
        except Exception as e:
            print(f"Disconnected: {e}")
        sleep_for = min(backoff * 2, 30) + random.uniform(0, 0.5)
        await asyncio.sleep(sleep_for)
        backoff = min(backoff * 2, 30)


if __name__ == "__main__":
    import contextlib

    asyncio.run(persistent_listener())
