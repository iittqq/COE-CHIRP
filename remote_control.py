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

        if cmd_type == "launch":
            package = data.get("package")
            if package:
                run_as_root(f"am start -n {package}")
                print(f"Launched package: {package}")

            await asyncio.sleep(20.0)

            ok, data = capture_ui_state_zipped()
            if ok:
                response["ui_state_zip_b64"] = data
            else:
                response["error"] = data

            await ws.send(json.dumps(response))

        elif cmd_type == "restart":
            package = data.get("package") or "eu.deeper.fishdeeper"
            activity = (
                data.get("activity") or "eu.deeper.app.scan.live.MainScreenActivity"
            )
            run_as_root(f"am force-stop {package}")
            await asyncio.sleep(5.0)
            run_as_root(f"am start -n {package}/{activity}")
            print(f"Restarted: {package}/{activity}")

            await asyncio.sleep(20.0)

            ok, data = capture_ui_state_zipped()
            if ok:
                response["ui_state_zip_b64"] = data
            else:
                response["error"] = data

            await ws.send(json.dumps(response))

        elif cmd_type == "close":
            package = data.get("package")
            if package:
                run_as_root(f"am force-stop {package}")
                print(f"Closed package: {package}")
                response["status"] = "closed"

                await asyncio.sleep(20.0)

                ok, data = capture_ui_state_zipped()
                if ok:
                    response["ui_state_zip_b64"] = data
                else:
                    response["error"] = data

                await ws.send(json.dumps(response))

        elif cmd_type == "wifi":
            state = data.get("state")
            if state == "on":
                run_as_root("svc wifi enable")
                print("Wi-Fi turned ON")
                response["status"] = "wifi_on"
            elif state == "off":
                run_as_root("svc wifi disable")
                print("Wi-Fi turned OFF")
                response["status"] = "wifi_off"
            else:
                response["status"] = "error"
                response["error"] = "Invalid state. Use 'on' or 'off'."

            ok, data = capture_ui_state_zipped()
            if ok:
                response["ui_state_zip_b64"] = data
            else:
                response["error"] = data

            await ws.send(json.dumps(response))
            return

        elif cmd_type == "checkOnline":
            ok, data = capture_ui_state_zipped()
            response["status"] = "online"
            if ok:
                response["ui_state_zip_b64"] = data
            else:
                response["error"] = data

            await ws.send(json.dumps(response))
            return

        elif cmd_type == "clickByXml":
            xml_node_str = data.get("xmlNode")
            if not xml_node_str:
                response["status"] = "error"
                response["error"] = "Missing xmlNode field"
            else:
                try:
                    import xml.etree.ElementTree as ET
                    import re

                    target_node = ET.fromstring(xml_node_str)
                    target_attribs = target_node.attrib

                    d = u2.connect()
                    print(
                        f"Searching for XML node matching: {target_attribs.get('content-desc') or target_attribs.get('text')}"
                    )

                    current_xml = d.dump_hierarchy()
                    root = ET.fromstring(current_xml)

                    clicked = False
                    for node in root.iter("node"):
                        match = all(
                            node.attrib.get(attr) == target_attribs.get(attr)
                            for attr in ["resource-id", "text", "class", "content-desc"]
                            if target_attribs.get(attr)
                        )

                        if match:
                            bounds = node.attrib.get("bounds")
                            if bounds:
                                m = re.findall(r"\d+", bounds)
                                if len(m) == 4:
                                    x1, y1, x2, y2 = map(int, m)
                                    cx = (x1 + x2) // 2
                                    cy = (y1 + y2) // 2

                                    d.click(cx, cy)
                                    print(
                                        f"Success: Tapped center of {bounds} at ({cx}, {cy})"
                                    )
                                    clicked = True
                                    break

                    response["status"] = "clicked_xml" if clicked else "not_found"

                    await asyncio.sleep(20.0)

                    ok, data = capture_ui_state_zipped()
                    if ok:
                        response["ui_state_zip_b64"] = data
                    else:
                        response["error"] = data

                    await ws.send(json.dumps(response))

                except Exception as e:
                    print(f"Error in clickByXml: {e}")
                    traceback.print_exc()
                    response["status"] = "error"
                    response["error"] = str(e)

        elif cmd_type == "swipeByXml":
            xml_node_str = data.get("xmlNode")
            end_x = data.get("endX")
            end_y = data.get("endY")
            duration = data.get("duration", 1200)

            if not all([xml_node_str, end_x is not None, end_y is not None]):
                response["status"] = "error"
                response["error"] = "Missing xmlNode, endX, or endY"
            else:
                try:
                    import xml.etree.ElementTree as ET
                    import re

                    target_node = ET.fromstring(xml_node_str)
                    target_attribs = target_node.attrib

                    d = u2.connect()
                    current_xml = d.dump_hierarchy()
                    root = ET.fromstring(current_xml)

                    swiped = False
                    for node in root.iter("node"):
                        match = all(
                            node.attrib.get(attr) == target_attribs.get(attr)
                            for attr in ["resource-id", "text", "class", "content-desc"]
                            if target_attribs.get(attr) is not None
                        )

                        if match:
                            bounds = node.attrib.get("bounds")
                            if bounds:
                                m = re.match(r"\[(\d+),(\d+)\]\[(\d+),(\d+)\]", bounds)
                                if m:
                                    x1, y1, x2, y2 = map(int, m.groups())
                                    start_x = (x1 + x2) // 2
                                    start_y = (y1 + y2) // 2

                                    run_as_root(
                                        f"input swipe {start_x} {start_y} {end_x} {end_y} {duration}"
                                    )
                                    print(
                                        f"Swiped from ({start_x}, {start_y}) to ({end_x}, {end_y})"
                                    )
                                    swiped = True
                                    break

                    response["status"] = "swiped_xml" if swiped else "node_not_found"

                    await asyncio.sleep(20.0)

                    ok, data = capture_ui_state_zipped()
                    if ok:
                        response["ui_state_zip_b64"] = data
                    else:
                        response["error"] = data

                    await ws.send(json.dumps(response))

                except Exception as e:
                    print(f"Error in swipeByXml: {e}")
                    traceback.print_exc()
                    response["status"] = "error"
                    response["error"] = str(e)

    except Exception as e:
        print("Error:", e)
        await ws.send(json.dumps({"error": str(e)}))


async def listen():
    try:
        async with connect(
            SERVER_URL,
            ping_interval=None,
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
                        break

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

    asyncio.run(persistent_listener())
