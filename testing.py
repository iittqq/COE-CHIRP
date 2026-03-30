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
    This version includes specialized commands for interacting with
    Flutter/cross-platform application UIs.
    """

    def __init__(self, server_url: str, default_package: str, default_activity: str):
        self.server_url = server_url
        self.default_package = default_package
        self.default_activity = default_activity
        self.d = None  # uiautomator2 device object
        self._command_handlers = {
            "launch": self._cmd_launch,
            "restart": self._cmd_restart,
            "close": self._cmd_close_app,
            "ping": self._cmd_ping,
            "dumpUi": self._cmd_dump_ui,
            "clickByXml": self._cmd_click_by_xml,
            "clickBySelector": self._cmd_click_by_selector,
            "inputText": self._cmd_input_text,
            "clickByIndex": self._cmd_click_by_index,  # NEW
            "clickById": self._cmd_click_by_id,  # NEW
        }

    # --- Utility Methods ---

    def _element_to_xml_string(self, element: ET.Element) -> str:
        """Converts an ElementTree.Element object back to its XML string representation."""
        return ET.tostring(element, encoding="unicode", method="xml")

    def _connect_u2(self):
        """Connects to the uiautomator2 service on the device."""
        if self.d is None:
            self.d = u2.connect()

        return self.d

    def _run_adb_shell(self, command: str):
        """Executes a command using 'su' (root) on the device."""
        print(f"Executing: {command}")
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

    def _find_node_by_index(
        self, index: str
    ) -> tuple[bool, str, tuple[int, int] | None]:
        """
        Finds a node by its index attribute and returns its bounds.
        Returns: (success, error_message, coordinates)
        """
        try:
            d = self._connect_u2()
            xml = d.dump_hierarchy()
            root = ET.fromstring(xml)

            # Search for node with matching index
            for node in root.iter("node"):
                if (
                    node.attrib.get("index") == index
                    and node.attrib.get("clickable") == "true"
                ):
                    bounds = node.attrib.get("bounds")
                    if bounds:
                        xy = self._parse_bounds(bounds)
                        if xy:
                            return True, "", xy
                        return False, f"Could not parse bounds: {bounds}", None
                    return False, "Node found but has no bounds attribute", None

            return False, f"No node found with index='{index}'", None
        except Exception as e:
            return False, f"Error searching for node: {str(e)}", None

    # --- Command Handlers ---

    async def _cmd_dump_ui(self, data: dict, ws):
        """Requests a UI dump."""
        print("Received dumpUi command. Capturing fresh UI state...")
        return {"status": "dumping"}

    async def _cmd_launch(self, data: dict, ws):
        """Launches a specific package."""
        package = data.get("package")
        if package:
            self._run_adb_shell(f"am start -n {package}")
            return {"status": "launched"}
        return {"status": "error", "error": "Missing package name"}

    async def _cmd_restart(self, data: dict, ws):
        """Force-stops and relaunches the default application."""
        package = data.get("package") or self.default_package
        activity = data.get("activity") or self.default_activity
        self._run_adb_shell(f"am force-stop {package}")
        await asyncio.sleep(3.0)
        self._run_adb_shell(f"am start -n {package}/{activity}")
        return {"status": "restarted"}

    async def _cmd_close_app(self, data: dict, ws):
        """Force-stops the specified Android application, effectively closing it."""

        package = data.get("package") or self.default_package

        print(f"Attempting to close app: {package}")

        self._run_adb_shell(f"am force-stop {package}")

        return {"status": "closed", "package": package}

    async def _cmd_ping(self, data: dict, ws) -> dict:
        """Responds to a ping request."""
        return {"status": "pong"}

    async def _cmd_click_by_xml(self, data: dict, ws):
        """
        Receives an XML node fragment string, parses it to extract bounds,
        and performs a tap at the calculated center coordinate.
        """
        xml_node_str = data.get("xmlNode")
        if not xml_node_str:
            return {"status": "error", "error": "Missing xmlNode field in command"}

        try:
            root = ET.fromstring(xml_node_str)
            bounds = root.attrib.get("bounds")

            if not bounds:
                return {
                    "status": "error",
                    "error": "XML node is missing 'bounds' attribute",
                }

            xy = self._parse_bounds(bounds)
            if xy:
                cx, cy = xy
                self._run_adb_shell(f"input tap {cx} {cy}")
                await asyncio.sleep(0.3)  # Small delay for tap registration
                print(f"Tapped coordinates from XML node bounds: ({cx}, {cy})")

                return {"status": "clicked_by_xml", "clicked_node_xml": xml_node_str}
            else:
                return {
                    "status": "error",
                    "error": f"Could not parse bounds string: {bounds}",
                }

        except ET.ParseError as e:
            return {"status": "error", "error": f"Invalid XML format provided: {e}"}
        except Exception as e:
            return {
                "status": "error",
                "error": f"An unexpected error occurred during XML click: {str(e)}",
            }

    async def _cmd_click_by_index(self, data: dict, ws):
        """
        Clicks an element by finding it via its 'index' attribute in the UI hierarchy.
        This is useful for elements that have no text, description, or resource-id.
        """
        index = data.get("index")
        if not index:
            return {"status": "error", "error": "Missing 'index' field in command"}

        print(f"Attempting to click element with index='{index}'")

        success, error_msg, xy = self._find_node_by_index(index)

        if success and xy:
            cx, cy = xy
            self._run_adb_shell(f"input tap {cx} {cy}")
            await asyncio.sleep(0.3)
            print(f"Tapped element at index '{index}': ({cx}, {cy})")
            return {
                "status": "clicked_by_index",
                "index": index,
                "coordinates": f"{cx},{cy}",
            }
        else:
            return {"status": "error", "error": error_msg}

    async def _cmd_click_by_id(self, data: dict, ws):
        """
        Clicks an element by its resource-id using uiautomator2.
        Fallback method for elements with resource IDs.
        """
        resource_id = data.get("resourceId")
        if not resource_id:
            return {"status": "error", "error": "Missing 'resourceId' field in command"}

        print(f"Attempting to click element with resource-id='{resource_id}'")

        try:
            d = self._connect_u2()
            locator = d(resourceId=resource_id)

            if not locator.exists(timeout=5):
                return {
                    "status": "error",
                    "error": f"Element not found: resourceId='{resource_id}'",
                }

            locator.click()
            await asyncio.sleep(0.3)
            print(f"Clicked element with resourceId='{resource_id}'")

            return {"status": "clicked_by_id", "resourceId": resource_id}

        except u2.exceptions.UiObjectNotFoundError:
            return {
                "status": "error",
                "error": f"Element not found: resourceId='{resource_id}'",
            }
        except Exception as e:
            return {"status": "error", "error": f"Error clicking by ID: {str(e)}"}

    async def _cmd_click_by_selector(self, data: dict, ws):
        """
        Clicks an element based on common selectors (text, description, xpath).
        This method is preferred for Flutter elements which expose text/description
        via accessibility services more reliably than resource-ids.
        """
        d = self._connect_u2()
        selector_type = None
        selector_value = None

        if data.get("text"):
            selector_type = "text"
            selector_value = data["text"]
            locator = d(text=selector_value)
        elif data.get("desc"):
            selector_type = "desc"
            selector_value = data["desc"]
            locator = d(description=selector_value)
        elif data.get("xpath"):
            selector_type = "xpath"
            selector_value = data["xpath"]
            locator = d.xpath(selector_value)
        elif data.get("resourceId"):
            selector_type = "resourceId"
            selector_value = data["resourceId"]
            locator = d(resourceId=selector_value)
        else:
            return {
                "status": "error",
                "error": "Missing required selector (text, desc, xpath, or resourceId)",
            }

        print(f"Attempting click using {selector_type}: '{selector_value}'")

        try:
            if not locator.exists(timeout=5):
                locator.click(timeout=1.0)
                if not locator.exists(timeout=1):
                    return {
                        "status": "error",
                        "error": f"Element not found after 5s: {selector_type}='{selector_value}'",
                    }

            locator.click()
            await asyncio.sleep(0.3)

            return {
                "status": "clicked_by_selector",
                "selector_type": selector_type,
                "selector_value": selector_value,
            }

        except u2.exceptions.UiObjectNotFoundError:
            return {
                "status": "error",
                "error": f"Element not found: {selector_type}='{selector_value}'",
            }
        except Exception as e:
            return {
                "status": "error",
                "error": f"Error during selector click: {str(e)}",
            }

    async def _cmd_input_text(self, data: dict, ws):
        """
        Inputs text into a field identified by a selector (text, desc, or xpath).
        """
        text_to_type = data.get("text_to_type")
        if not text_to_type:
            return {"status": "error", "error": "Missing 'text_to_type' field"}

        d = self._connect_u2()
        selector_type = None
        selector_value = None

        if data.get("text"):
            selector_type = "text"
            selector_value = data["text"]
            locator = d(text=selector_value)
        elif data.get("desc"):
            selector_type = "desc"
            selector_value = data["desc"]
            locator = d(description=selector_value)
        elif data.get("xpath"):
            selector_type = "xpath"
            selector_value = data["xpath"]
            locator = d.xpath(selector_value)
        elif data.get("resourceId"):
            selector_type = "resourceId"
            selector_value = data["resourceId"]
            locator = d(resourceId=selector_value)
        else:
            # Fallback: if no selector is provided, assume the currently focused element
            try:
                d.send_keys(text_to_type, clear=True)
                return {"status": "input_sent_to_focused", "text_typed": text_to_type}
            except Exception as e:
                return {
                    "status": "error",
                    "error": f"Could not type into focused element: {str(e)}",
                }

        print(f"Attempting text input using {selector_type}: '{selector_value}'")

        try:
            if not locator.exists(timeout=5):
                return {
                    "status": "error",
                    "error": f"Input field not found: {selector_type}='{selector_value}'",
                }

            locator.set_text(text_to_type)

            return {
                "status": "input_sent_by_selector",
                "selector_type": selector_type,
                "selector_value": selector_value,
                "text_typed": text_to_type,
            }

        except u2.exceptions.UiObjectNotFoundError:
            return {
                "status": "error",
                "error": f"Input field not found: {selector_type}='{selector_value}'",
            }
        except Exception as e:
            return {"status": "error", "error": f"Error during text input: {str(e)}"}

    async def handle_command(self, ws, command: str):
        """Parses and executes a command received over WebSocket."""
        response = {"status": "error"}
        cmd_type = None

        try:
            data = json.loads(command)

            if data.get("message") in ("Forbidden", "forbidden"):
                return

            # Handle commands possibly nested in a 'body' string
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
            commands_to_skip_sleep = ["ping", "dumpUi"]

            # Wait only if a UI-changing command was executed
            if (
                cmd_type in self._command_handlers
                and cmd_type not in commands_to_skip_sleep
            ):
                print(f"Waiting 10.0s after UI-changing command: {cmd_type}")
                await asyncio.sleep(10.0)

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
        self._connect_u2()
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

            sleep_for = min(backoff * 2, 30) + random.uniform(0, 0.5)
            print(f"Retrying connection in {sleep_for:.2f}s...")
            await asyncio.sleep(sleep_for)
            backoff = min(backoff * 2, 30)


if __name__ == "__main__":
    agent = AndroidUIAgent(SERVER_URL, DEFAULT_PACKAGE, DEFAULT_ACTIVITY)
    asyncio.run(agent.persistent_listener())
