// Backend endpoints come from Vite env vars (see .env.example). Copy it to
// .env.local, which is gitignored, and fill in your own deployment's URLs.
function requireEnv(name: "VITE_API_BASE_URL" | "VITE_WS_URL"): string {
  const value = import.meta.env[name] as string | undefined;
  if (!value) {
    throw new Error(
      `${name} is not set. Copy .env.example to .env.local and fill it in.`,
    );
  }
  return value;
}

export const API_BASE_URL = requireEnv("VITE_API_BASE_URL");
export const WS_URL = requireEnv("VITE_WS_URL");
