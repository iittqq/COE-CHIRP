export type MessageListener = (data: Record<string, unknown>) => void;
export type DisconnectListener = () => void;

export class WebSocketService {
  private deviceId: string;
  private apiUrl: string;
  private socket: WebSocket | null = null;
  private messageListeners = new Set<MessageListener>();
  private disconnectListeners = new Set<DisconnectListener>();

  constructor(
    deviceId: string,
    apiUrl = "wss://ywh1uzhhk9.execute-api.us-east-2.amazonaws.com/test",
  ) {
    this.deviceId = deviceId;
    this.apiUrl = apiUrl;
  }

  connect(): Promise<void> {
    const url = `${this.apiUrl}?deviceId=${encodeURIComponent(this.deviceId)}`;
    console.log(`Connecting to ${url} ...`);

    // Callers re-register their message/disconnect listeners after every
    // successful connect() (including reconnects) — clear stale ones first
    // so a reconnect doesn't leave the old socket's listeners stacked on
    // top of the new ones.
    this.messageListeners.clear();
    this.disconnectListeners.clear();

    return new Promise((resolve, reject) => {
      let settled = false;
      const socket = new WebSocket(url);
      this.socket = socket;

      socket.onopen = () => {
        settled = true;
        console.log("Connected to WebSocket");
        resolve();
      };

      socket.onmessage = (event) => {
        try {
          const decoded = JSON.parse(event.data);
          for (const listener of this.messageListeners) listener(decoded);
        } catch {
          console.log(`Invalid message: ${event.data}`);
        }
      };

      socket.onerror = (event) => {
        console.log("WebSocket error", event);
        if (!settled) {
          settled = true;
          reject(event);
        } else {
          for (const listener of this.disconnectListeners) listener();
        }
      };

      socket.onclose = () => {
        console.log("WebSocket closed");
        if (!settled) {
          settled = true;
          reject(new Error("WebSocket closed before opening"));
        } else {
          for (const listener of this.disconnectListeners) listener();
        }
      };
    });
  }

  onMessage(listener: MessageListener): () => void {
    this.messageListeners.add(listener);
    return () => this.messageListeners.delete(listener);
  }

  onDisconnect(listener: DisconnectListener): () => void {
    this.disconnectListeners.add(listener);
    return () => this.disconnectListeners.delete(listener);
  }

  sendCommand(command: Record<string, unknown>): void {
    if (!this.socket || this.socket.readyState !== WebSocket.OPEN) {
      console.log("WebSocket not connected.");
      return;
    }
    const payload = JSON.stringify(command);
    this.socket.send(payload);
    console.log(`Sent: ${payload}`);
  }

  disconnect(): void {
    this.messageListeners.clear();
    this.disconnectListeners.clear();
    this.socket?.close(1000);
    this.socket = null;
    console.log("Disconnected WebSocket");
  }
}
