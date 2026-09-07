// Talks to the auth Lambda deployed behind the same API Gateway/base URL as
// the sonar CRUD endpoints (see sonarRepository.ts). Session identity is a
// small JSON blob cached in localStorage - presence of that key means the
// user is "logged in" for the purposes of gating the app shell in App.tsx.
const BASE_URL = "https://078qjv1849.execute-api.us-east-2.amazonaws.com";

const SESSION_KEY = "chirp_account";

export interface AccountSession {
  email: string;
  user_id: string;
}

export function getSession(): AccountSession | null {
  const raw = localStorage.getItem(SESSION_KEY);
  if (!raw) return null;
  try {
    const parsed = JSON.parse(raw) as Partial<AccountSession>;
    if (typeof parsed.email === "string" && typeof parsed.user_id === "string") {
      return { email: parsed.email, user_id: parsed.user_id };
    }
  } catch {
    // Malformed cache entry - treat as logged out.
  }
  return null;
}

export function setSession(session: AccountSession): void {
  localStorage.setItem(SESSION_KEY, JSON.stringify(session));
}

export function clearSession(): void {
  localStorage.removeItem(SESSION_KEY);
}

interface AuthResponseBody {
  user_id?: string;
  email?: string;
  error?: string;
}

async function authRequest(
  action: "register" | "login" | "reset_password",
  email: string,
  password: string,
): Promise<AccountSession> {
  const response = await fetch(`${BASE_URL}/auth`, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({ action, email, password }),
  });

  const data = (await response.json().catch(() => ({}))) as AuthResponseBody;

  if (!response.ok || !data.user_id || !data.email) {
    throw new Error(data.error || `Request failed (${response.status})`);
  }

  return { user_id: data.user_id, email: data.email };
}

export async function registerAccount(
  email: string,
  password: string,
): Promise<AccountSession> {
  return authRequest("register", email, password);
}

export async function loginAccount(
  email: string,
  password: string,
): Promise<AccountSession> {
  return authRequest("login", email, password);
}

// PoC "forgot password": sets a new password for the account with this email
// with no verification step (see the Lambda's _reset_password). On success the
// returned session logs the user straight in.
export async function resetPassword(
  email: string,
  newPassword: string,
): Promise<AccountSession> {
  return authRequest("reset_password", email, newPassword);
}
