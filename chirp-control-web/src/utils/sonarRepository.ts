// Replace with your API Gateway invoke URL after deploying the Lambda.
const BASE_URL = "https://078qjv1849.execute-api.us-east-2.amazonaws.com";

const USER_ID_KEY = "chirp_device_user_id";

export interface Sonar {
  sonar_id: string;
  name: string;
  status?: string;
}

type Listener = () => void;

// Notified whenever the registered sonar list changes (add/delete), so
// screens that cache their own copy (Home, Scan) know to refetch instead of
// only loading once on mount.
class SonarsChangedEmitter {
  private listeners = new Set<Listener>();

  subscribe(listener: Listener): () => void {
    this.listeners.add(listener);
    return () => this.listeners.delete(listener);
  }

  emit(): void {
    for (const listener of this.listeners) listener();
  }
}

export const sonarsChanged = new SonarsChangedEmitter();

function getUserId(): string {
  let userId = localStorage.getItem(USER_ID_KEY);
  if (!userId) {
    userId = crypto.randomUUID();
    localStorage.setItem(USER_ID_KEY, userId);
  }
  return userId;
}

async function fetchSonarsFor(userId: string): Promise<Sonar[]> {
  const response = await fetch(
    `${BASE_URL}/sonars?user_id=${encodeURIComponent(userId)}`,
  );
  if (!response.ok) {
    throw new Error(
      `Failed to load sonars (${response.status}): ${await response.text()}`,
    );
  }
  const data = await response.json();
  return data.sonars as Sonar[];
}

export async function fetchSonars(): Promise<Sonar[]> {
  return fetchSonarsFor(getUserId());
}

export async function addSonar(name: string, sonarId: string): Promise<void> {
  const response = await fetch(`${BASE_URL}/sonars`, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({
      user_id: getUserId(),
      sonar_id: sonarId,
      name,
      status: "Active",
    }),
  });
  if (!response.ok) {
    throw new Error(`Failed to add sonar (${response.status})`);
  }
  sonarsChanged.emit();
}

export async function deleteSonar(sonarId: string): Promise<void> {
  const response = await fetch(
    `${BASE_URL}/sonars?user_id=${encodeURIComponent(getUserId())}&sonar_id=${encodeURIComponent(sonarId)}`,
    { method: "DELETE" },
  );
  if (!response.ok) {
    throw new Error(`Failed to delete sonar (${response.status})`);
  }
  sonarsChanged.emit();
}
