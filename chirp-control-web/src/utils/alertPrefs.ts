const SONAR_ALERTS_KEY = "settings_sonar_alerts";
const DREDGE_WARNINGS_KEY = "settings_dredge_warnings";

function loadFlag(key: string): boolean {
  const raw = localStorage.getItem(key);
  return raw === null ? true : raw === "true";
}

function saveFlag(key: string, value: boolean): void {
  localStorage.setItem(key, String(value));
}

export function loadSonarAlertsEnabled(): boolean {
  return loadFlag(SONAR_ALERTS_KEY);
}

export function saveSonarAlertsEnabled(value: boolean): void {
  saveFlag(SONAR_ALERTS_KEY, value);
}

export function loadDredgeWarningsEnabled(): boolean {
  return loadFlag(DREDGE_WARNINGS_KEY);
}

export function saveDredgeWarningsEnabled(value: boolean): void {
  saveFlag(DREDGE_WARNINGS_KEY, value);
}
