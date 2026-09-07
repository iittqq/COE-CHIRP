import { getSession } from "./auth";

// Replace with your API Gateway invoke URL after deploying the Lambda.
const BASE_URL = "https://078qjv1849.execute-api.us-east-2.amazonaws.com";

// Pre-auth, every browser install got a random anonymous id cached under
// this key and sonars were registered under it. Now that real accounts
// exist, `getUserId()` returns the logged-in account's user_id instead -
// but this key (and any sonars already sitting under it in DynamoDB) has to
// stay reachable so `migrateLegacySonarsIfNeeded` can claim them for the
// first account that logs in on this browser. Don't delete this constant or
// stop reading it; devices that registered sonars before auth existed have
// no other way to find them again.
const LEGACY_ANONYMOUS_USER_ID_KEY = "chirp_device_user_id";
const LEGACY_MIGRATED_KEY = "chirp_legacy_sonars_migrated";

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
  const session = getSession();
  if (!session) {
    throw new Error("getUserId() called with no active session. The user must be logged in.");
  }
  return session.user_id;
}

function getLegacyAnonymousUserId(): string | null {
  return localStorage.getItem(LEGACY_ANONYMOUS_USER_ID_KEY);
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

async function addSonarFor(
  userId: string,
  name: string,
  sonarId: string,
  status = "Active",
): Promise<void> {
  const response = await fetch(`${BASE_URL}/sonars`, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({
      user_id: userId,
      sonar_id: sonarId,
      name,
      status,
    }),
  });
  if (!response.ok) {
    throw new Error(`Failed to add sonar (${response.status})`);
  }
}

async function deleteSonarFor(userId: string, sonarId: string): Promise<void> {
  const response = await fetch(
    `${BASE_URL}/sonars?user_id=${encodeURIComponent(userId)}&sonar_id=${encodeURIComponent(sonarId)}`,
    { method: "DELETE" },
  );
  if (!response.ok) {
    throw new Error(`Failed to delete sonar (${response.status})`);
  }
}

export async function fetchSonars(): Promise<Sonar[]> {
  return fetchSonarsFor(getUserId());
}

export async function addSonar(name: string, sonarId: string): Promise<void> {
  await addSonarFor(getUserId(), name, sonarId);
  sonarsChanged.emit();
}

export async function deleteSonar(sonarId: string): Promise<void> {
  await deleteSonarFor(getUserId(), sonarId);
  sonarsChanged.emit();
}

// Runs once per browser install, after a successful login or register. Any
// sonars still registered under the pre-auth anonymous id are re-registered
// under the now-logged-in account's user_id and removed from the legacy id,
// so a returning user doesn't see an empty sonar list just because they now
// have a real account. Only marks itself done on success (or when there was
// nothing to migrate) - a failed attempt (e.g. offline) leaves the flag
// unset so it's retried on the next login instead of silently giving up.
// Intentionally fire-and-forget from the caller's perspective: don't await
// this before letting the user into the app.
export async function migrateLegacySonarsIfNeeded(): Promise<void> {
  if (localStorage.getItem(LEGACY_MIGRATED_KEY) === "true") return;

  const legacyId = getLegacyAnonymousUserId();
  if (!legacyId) {
    localStorage.setItem(LEGACY_MIGRATED_KEY, "true");
    return;
  }

  let targetUserId: string;
  try {
    targetUserId = getUserId();
  } catch {
    return; // No session yet - nothing to migrate into.
  }

  if (legacyId === targetUserId) {
    localStorage.setItem(LEGACY_MIGRATED_KEY, "true");
    return;
  }

  try {
    const legacySonars = await fetchSonarsFor(legacyId);
    for (const sonar of legacySonars) {
      await addSonarFor(targetUserId, sonar.name, sonar.sonar_id, sonar.status ?? "Active");
      await deleteSonarFor(legacyId, sonar.sonar_id);
    }
    localStorage.setItem(LEGACY_MIGRATED_KEY, "true");
    if (legacySonars.length > 0) sonarsChanged.emit();
  } catch {
    // Offline or API error - leave the flag unset so this retries on the
    // next login/register instead of losing the legacy sonars silently.
  }
}
