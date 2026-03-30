import asyncio
import subprocess
import json
import random
import traceback
import gzip
import base64
import re
import xml.etree.ElementTree as ET
from io import BytesIO
from websockets import connect, ConnectionClosed
import uiautomator2 as u2

# --- Configuration ---
SERVER_URL = (
    "wss://ywh1uzhhk9.execute-api.us-east-2.amazonaws.com/test?deviceId=testAndroid"
)
DEFAULT_PACKAGE = "eu.deeper.fishdeeper"
DEFAULT_ACTIVITY = "eu.deeper.app.scan.live.MainScreenActivity"


class AndroidUIAgent:
    """
    A persistent WebSocket client for remote Android UI automation.
    """

    def __init__(self, server_url: str, default_package: str, default_activity: str):
        self.server_url = server_url
        self.default_package = default_package
        self.default_activity = default_activity
        self.d = None  # uiautomator2 device object
        self._command_handlers = {
            "tap": self._cmd_tap,
            "swipe": self._cmd_swipe,
            "launch": self._cmd_launch,
            "restart": self._cmd_restart,
            "ping": self._cmd_ping,
            "dumpUi": self._cmd_dump_ui,
            "clickText": self._cmd_click_text,
            "clickById": self._cmd_click_by_id,
            "clickByIndex": self._cmd_click_by_index,
            "clickTextDirect": self._cmd_click_text_direct,
            "clickByDescription": self._cmd_click_by_description,
        }

    # --- Utility Methods ---

    def _connect_u2(self):
        """Connects to the uiautomator2 service on the device."""
        if self.d is None:
            self.d = u2.connect()
        return self.d

    def _run_adb_shell(self, command: str):
        """Executes a command using 'su' (root) on the device."""
        print(f"Executing: {command}")
        # Note: Using Popen/communicate pattern to match original
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

    def _get_ui_state_zip_b64(self) -> tuple[bool, str]:
        """Captures, compresses (gzip), and Base64 encodes the UI hierarchy XML."""
        try:
            d = self._connect_u2()
            xml = d.dump_hierarchy()

            buf = BytesIO()
            with gzip.GzipFile(fileobj=buf, mode="wb") as f:
                f.write(xml.encode("utf-8"))

            compressed_b64 = base64.b64encode(buf.getvalue()).decode("utf-8")
            return True, compressed_b64
        except Exception as e:
            return False, str(e)

    def _parse_bounds(self, bounds: str) -> tuple[int, int] | None:
        """Parses [x1,y1][x2,y2] bounds string to find the center point (cx, cy)."""
        m = re.match(r"\[(\d+),(\d+)\]\[(\d+),(\d+)\]", bounds)
        if not m:
            return None
        x1, y1, x2, y2 = map(int, m.groups())
        return (x1 + x2) // 2, (y1 + y2) // 2

    # --- Command Handlers ---

    async def _cmd_dump_ui(self, data: dict, ws):
        """
        Requests a UI dump. The actual dump and send logic is handled
        in the handle_command finally block, but this handler exists
        to ensure the command is recognized and the 10.0s sleep is skipped.
        """
        print("Received dumpUi command. Capturing fresh UI state...")
        # Since the dump logic is in finally, we just return a success status here.
        return {"status": "dumping"}

    async def _cmd_tap(self, data: dict, ws):
        x, y = data.get("x"), data.get("y")
        if x is not None and y is not None:
            self._run_adb_shell(f"input tap {x} {y}")

    async def _cmd_swipe(self, data: dict, ws):
        x1, y1, x2, y2 = data.get("x1"), data.get("y1"), data.get("x2"), data.get("y2")
        duration = data.get("duration", 300)
        self._run_adb_shell(f"input swipe {x1} {y1} {x2} {y2} {duration}")

    async def _cmd_launch(self, data: dict, ws):
        package = data.get("package")
        if package:
            self._run_adb_shell(f"am start -n {package}")

    async def _cmd_restart(self, data: dict, ws):
        package = data.get("package") or self.default_package
        activity = data.get("activity") or self.default_activity
        self._run_adb_shell(f"am force-stop {package}")
        await asyncio.sleep(1.0)
        self._run_adb_shell(f"am start -n {package}/{activity}")

    async def _cmd_ping(self, data: dict, ws) -> dict:
        return {"status": "pong"}

    async def _cmd_click_text(self, data: dict, ws):
        d = self._connect_u2()
        txt = data.get("text")
        if not txt:
            return {"status": "error", "error": "Missing text field"}

        response = {}
        clicked = False
        print(f"Searching for exact text: '{txt}'")
        node = d(text=txt)

        # Logic for exact text match (click direct or clickable ancestor)
        if node.exists:
            info = node.info
            if info.get("clickable"):
                node.click()
                print(f"Clicked directly on clickable exact text: {txt}")
                clicked = True
            else:
                # Find clickable parent
                parent = d.xpath(f"//*[@text='{txt}']/ancestor::*[@clickable='true']")
                parents = parent.all()
                if parents:
                    parents[0].click()
                    print(f"Clicked clickable ancestor for exact '{txt}'")
                    clicked = True
                else:
                    # Fallback click on bounds if not clickable and no clickable ancestor
                    node.click_exists(timeout=3.0)
                    print(f"Fallback clicked node bounds for '{txt}'")
                    clicked = True

        if not clicked:
            print(f"Searching for partial text: '{txt}'")
            # Logic for partial text match
            for obj in d.xpath(f"//*[contains(@text,'{txt}')]").all():
                info = obj.info
                if info.get("clickable"):
                    obj.click()
                    print(f"Clicked clickable element containing '{txt}'")
                    clicked = True
                    break
                else:
                    # Find clickable parent for partial match
                    parent = d.xpath(
                        f"//*[contains(@text,'{txt}')]/ancestor::*[@clickable='true']"
                    )
                    parents = parent.all()
                    if parents:
                        parents[0].click()
                        print(f"Clicked clickable ancestor for partial '{txt}'")
                        clicked = True
                        break

        response["status"] = "clicked" if clicked else "not_found"
        return response

    async def _cmd_click_by_id(self, data: dict, ws):
        d = self._connect_u2()
        rid = data.get("resourceId")
        if not rid:
            return {"status": "error", "error": "Missing resourceId field"}

        # Find the target node in the hierarchy
        xml_str = d.dump_hierarchy()
        root = ET.fromstring(xml_str)

        target_node = root.find(f".//*[@resource-id='{rid}']")

        if target_node is None:
            print(f"No node found with resource-id='{rid}'")
            return {"status": "not_found"}

        # Try to find a clickable ancestor or the node itself

        # 1. Try direct click if node is clickable
        if target_node.attrib.get("clickable") == "true":
            bounds = target_node.attrib.get("bounds")
            if bounds:
                xy = self._parse_bounds(bounds)
                if xy:
                    cx, cy = xy
                    self._run_adb_shell(f"input tap {cx} {cy}")
                    print(
                        f"Tapped directly on clickable element by ID at ({cx}, {cy}) for '{rid}'"
                    )
                    return {"status": "clicked_direct"}

        # 2. Try clickable ancestor
        current = target_node.find("..")  # Start with parent
        while current is not None and current.tag == "node":
            if current.attrib.get("clickable") == "true":
                bounds = current.attrib.get("bounds")
                if bounds:
                    xy = self._parse_bounds(bounds)
                    if xy:
                        cx, cy = xy
                        self._run_adb_shell(f"input tap {cx} {cy}")
                        print(
                            f"Tapped clickable ancestor by ID at ({cx}, {cy}) for '{rid}'"
                        )
                        return {"status": "clicked_ancestor"}
                break
            current = current.find("..")

        # 3. Fallback: click target node's bounds
        bounds = target_node.attrib.get("bounds")
        if bounds:
            xy = self._parse_bounds(bounds)
            if xy:
                cx, cy = xy
                self._run_adb_shell(f"input tap {cx} {cy}")
                print(
                    f"Tapped fallback on node bounds by ID at ({cx}, {cy}) for '{rid}'"
                )
                return {"status": "clicked_fallback"}

        # 4. Final failure
        return {"status": "no_clickable_or_bounds"}

    async def _cmd_click_by_index(self, data: dict, ws):
        """
        Clicks an element found by its XML 'index' attribute.
        Uses a two-pass strategy: prioritize elements that are themselves clickable,
        then fall back to checking for a clickable ancestor.
        """
        d = self._connect_u2()
        try:
            index = str(data.get("index"))
            if not index:
                return {"status": "error", "error": "Missing index field"}
        except ValueError:
            return {"status": "error", "error": "Invalid index value"}

        print(f"Searching XML for all nodes with index='{index}'")
        xml_str = d.dump_hierarchy()
        root = ET.fromstring(xml_str)

        # 1. Use findall to get all nodes matching the index
        target_nodes = root.findall(f".//*[@index='{index}']")

        if not target_nodes:
            print(f"No node found with index='{index}'")
            return {"status": "not_found"}

        first_node = target_nodes[0]

        # --- PASS 1: Find and click the first element that is ITSELF clickable ---
        for target_node in target_nodes:
            if target_node.attrib.get("clickable") == "true":
                node_class = target_node.attrib.get("class")
                node_bounds = target_node.attrib.get("bounds")

                # We need a unique XPath to click the exact element via uiautomator2
                if node_class and node_bounds:
                    unique_xpath = f"//{node_class}[@bounds='{node_bounds}']"
                    try:
                        d.xpath(unique_xpath).click()
                        print(
                            f"PASS 1: Tapped directly on clickable element (self) by index at ({node_bounds}) for '{index}'"
                        )
                        return {"status": "clicked_direct"}
                    except Exception as e:
                        print(
                            f"Click failed on clickable node (index={index}, bounds={node_bounds}): {e}. Trying next match."
                        )
                        continue  # Continue to next match in Pass 1

        # --- PASS 2: If no self-clickable match found, find the first non-clickable node with a clickable ancestor ---
        print(
            "PASS 2: No self-clickable match found. Checking for clickable ancestors."
        )
        for target_node in target_nodes:
            if target_node.attrib.get("clickable") != "true":
                node_class = target_node.attrib.get("class")
                node_bounds = target_node.attrib.get("bounds")

                if not node_class or not node_bounds:
                    continue

                unique_xpath = f"//{node_class}[@bounds='{node_bounds}']"
                ancestor_xpath = f"{unique_xpath}/ancestor::*[@clickable='true']"

                clickable_ancestors = d.xpath(ancestor_xpath).all()

                if clickable_ancestors:
                    # Click the closest clickable ancestor
                    clickable_ancestors[0].click()
                    bounds = clickable_ancestors[0].info["bounds"]
                    print(
                        f"PASS 2: Tapped clickable ancestor by index at ({bounds}) for '{index}'"
                    )
                    return {"status": "clicked_ancestor"}

        # --- Fallback: If no clickable element was found after iterating all matches ---

        print(
            f"FINAL FALLBACK: No explicitly clickable element or clickable ancestor found for index='{index}' across all matches. Falling back to tapping the first match found."
        )

        bounds = first_node.attrib.get("bounds")
        if bounds:
            xy = self._parse_bounds(bounds)
            if xy:
                cx, cy = xy
                self._run_adb_shell(f"input tap {cx} {cy}")
                print(
                    f"Tapped fallback on FIRST node bounds by index at ({cx}, {cy}) for '{index}' (Not clickable)"
                )
                return {"status": "clicked_fallback_non_clickable"}

        # Final failure
        return {"status": "no_clickable_or_bounds"}

    async def _cmd_click_text_direct(self, data: dict, ws):
        # NOTE: This command is largely redundant with the improved _cmd_click_text
        # but is kept for compatibility with the original structure.
        d = self._connect_u2()
        txt = data.get("text")
        if not txt:
            return {"status": "error", "error": "Missing text field"}

        xml_str = d.dump_hierarchy()
        root = ET.fromstring(xml_str)
        target_bounds = None

        for node in root.iter("node"):
            if node.attrib.get("text") == txt:
                target_bounds = node.attrib.get("bounds")
                break

        if target_bounds:
            xy = self._parse_bounds(target_bounds)
            if xy:
                cx, cy = xy
                self._run_adb_shell(f"input tap {cx} {cy}")
                print(f"Tapped directly at ({cx},{cy}) for '{txt}'")
                return {"status": "clicked_direct_text"}
            else:
                return {"status": "bad_bounds"}
        else:
            print(f"No node found with text='{txt}'")
            return {"status": "not_found"}

    async def _cmd_click_by_description(self, data: dict, ws):
        d = self._connect_u2()
        desc = data.get("description")
        if not desc:
            return {"status": "error", "error": "Missing description field"}

        response = {}
        clicked = False
        print(f"Searching for content-desc: '{desc}'")

        # Try description first, then fallback to text
        node = d(description=desc)
        if not node.exists:
            node = d(text=desc)

        if node.exists:
            info = node.info
            if info.get("clickable"):
                node.click()
                print(f"Clicked directly on clickable description/text element: {desc}")
                clicked = True
            else:
                # Find clickable parent
                xpath_query_desc = (
                    f"//*[@content-desc='{desc}']/ancestor::*[@clickable='true']"
                )
                xpath_query_text = f"//*[@text='{desc}']/ancestor::*[@clickable='true']"

                parent = d.xpath(xpath_query_desc)
                parents = parent.all()

                if not parents:
                    parent = d.xpath(xpath_query_text)
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
        return response

    # --- Core WebSocket Logic ---

    async def handle_command(self, ws, command: str):
        """Parses and executes a command received over WebSocket."""
        response = {"status": "error"}  # Default error status
        cmd_type = None

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

            # Route command to handler
            handler = self._command_handlers.get(cmd_type)
            if handler:
                handler_response = await handler(data, ws)
                if handler_response:
                    response.update(handler_response)
            else:
                response["status"] = "unsupported_command"
                response["error"] = f"Unknown command type: {cmd_type}"

        except Exception as e:
            print(f"Error handling command '{cmd_type}':", e)
            traceback.print_exc()
            response["status"] = "error"
            response["error"] = str(e)
        finally:
            # Send UI state and response back

            # FIX 3: Skip the long 10.0s sleep for commands that only request state (ping, dumpUi)
            commands_to_skip_sleep = ["ping", "dumpUi"]

            # Wait only if a UI-changing command was executed
            if (
                cmd_type in self._command_handlers
                and cmd_type not in commands_to_skip_sleep
            ):
                print(f"Waiting 10.0s after UI-changing command: {cmd_type}")
                await asyncio.sleep(10.0)  # Maintain original wait time

            # Capture and attach UI dump to the response
            ok, ui_data = self._get_ui_state_zip_b64()
            if ok:
                response["ui_state_zip_b64"] = ui_data
            else:
                response["error"] = (
                    response.get("error", "") + f" | UI capture error: {ui_data}"
                )

            await ws.send(json.dumps(response))

    async def listen(self):
        """Connects to the WebSocket server and starts listening for commands."""
        print(f"Attempting connection to: {self.server_url}")
        async with connect(
            self.server_url,
            ping_interval=None,
            ping_timeout=None,
            close_timeout=5,
            max_size=2**20,
        ) as ws:
            print("Connected.")

            async def receiver():
                while True:
                    try:
                        msg = await ws.recv()
                        print("Raw message:", msg)
                        await self.handle_command(ws, msg)
                    except ConnectionClosed as cc:
                        print(
                            f"[receiver] Connection closed: code={cc.code} reason={cc.reason}"
                        )
                        raise
                    except Exception:
                        print(
                            "[receiver] Exception while receiving or handling message:"
                        )
                        traceback.print_exc()
                        break

            await receiver()

    async def persistent_listener(self):
        """Continuously attempts to connect and listen, with exponential backoff."""
        backoff = 1
        while True:
            try:
                await self.listen()
                backoff = 1
            except ConnectionClosed as cc:
                print(f"Closed: code={cc.code} reason={cc.reason}")
            except Exception as e:
                print(f"Disconnected: {e}")

            # Exponential backoff with a max of 30 seconds and slight jitter
            sleep_for = min(backoff * 2, 30) + random.uniform(0, 0.5)
            await asyncio.sleep(sleep_for)
            backoff = min(backoff * 2, 30)


if __name__ == "__main__":
    agent = AndroidUIAgent(SERVER_URL, DEFAULT_PACKAGE, DEFAULT_ACTIVITY)
    asyncio.run(agent.persistent_listener())
