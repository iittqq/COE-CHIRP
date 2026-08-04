const IS_METRIC_KEY = "units_is_metric";

export function loadIsMetric(): boolean {
  const raw = localStorage.getItem(IS_METRIC_KEY);
  return raw === null ? true : raw === "true";
}

export function saveIsMetric(isMetric: boolean): void {
  localStorage.setItem(IS_METRIC_KEY, String(isMetric));
}

export function cmToDisplayUnit(cm: number, isMetric: boolean): number {
  return isMetric ? cm : cm / 2.54;
}

export function depthUnitLabel(isMetric: boolean): string {
  return isMetric ? "cm" : "in";
}
