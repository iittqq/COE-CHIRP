export interface WeatherLocation {
  name: string;
  latitude: number;
  longitude: number;
  timezone: string;
}

export const defaultWeatherLocation: WeatherLocation = {
  name: "29.80, -93.33",
  latitude: 29.7977,
  longitude: -93.3251,
  timezone: "America/Chicago",
};

const WEATHER_LAT_KEY = "weather_location_lat";
const WEATHER_LON_KEY = "weather_location_lon";
const WEATHER_TZ_KEY = "weather_location_tz";
const WEATHER_NAME_KEY = "weather_location_name";

export function loadSavedWeatherLocation(): WeatherLocation {
  const lat = localStorage.getItem(WEATHER_LAT_KEY);
  const lon = localStorage.getItem(WEATHER_LON_KEY);

  if (lat === null || lon === null) return defaultWeatherLocation;

  return {
    name: localStorage.getItem(WEATHER_NAME_KEY) ?? `${lat}, ${lon}`,
    latitude: parseFloat(lat),
    longitude: parseFloat(lon),
    timezone: localStorage.getItem(WEATHER_TZ_KEY) ?? "auto",
  };
}

export function saveWeatherLocation(location: WeatherLocation): void {
  localStorage.setItem(WEATHER_LAT_KEY, String(location.latitude));
  localStorage.setItem(WEATHER_LON_KEY, String(location.longitude));
  localStorage.setItem(WEATHER_TZ_KEY, location.timezone);
  localStorage.setItem(WEATHER_NAME_KEY, location.name);
}

export async function searchWeatherLocations(
  query: string,
): Promise<WeatherLocation[]> {
  const url = new URL("https://geocoding-api.open-meteo.com/v1/search");
  url.searchParams.set("name", query);
  url.searchParams.set("count", "5");
  url.searchParams.set("language", "en");
  url.searchParams.set("format", "json");

  const response = await fetch(url);
  if (!response.ok) {
    throw new Error("Failed to search locations");
  }

  const decoded = await response.json();
  const results = decoded.results as
    | Array<{
        name?: string;
        admin1?: string;
        country?: string;
        latitude: number;
        longitude: number;
        timezone?: string;
      }>
    | undefined;

  if (!results) return [];

  return results.map((result) => {
    const nameParts = [result.name, result.admin1, result.country].filter(
      (part): part is string => !!part && part.length > 0,
    );

    return {
      name: nameParts.join(", "),
      latitude: result.latitude,
      longitude: result.longitude,
      timezone: result.timezone ?? "auto",
    };
  });
}

export interface Weather {
  hourlyUnits: Record<string, unknown>;
  times: string[];
  temperatures: number[];
  rainChances: number[];
  showerChances: number[];
  cloudCovers: number[];
  sunshineDuration: number[];
}

export async function fetchWeather(
  location: WeatherLocation,
): Promise<Weather> {
  const url = new URL("https://api.open-meteo.com/v1/forecast");
  url.searchParams.set("latitude", String(location.latitude));
  url.searchParams.set("longitude", String(location.longitude));
  url.searchParams.set(
    "hourly",
    "temperature_2m,rain,showers,cloud_cover,sunshine_duration",
  );
  url.searchParams.set("timezone", location.timezone);
  url.searchParams.set("wind_speed_unit", "mph");
  url.searchParams.set("temperature_unit", "fahrenheit");
  url.searchParams.set("precipitation_unit", "inch");
  url.searchParams.set("forecast_hours", "24");

  const response = await fetch(url);
  if (!response.ok) {
    throw new Error("Failed to load weather");
  }

  const json = await response.json();
  const hourlyUnits = json.hourly_units;
  const hourly = json.hourly;

  if (!hourlyUnits || !hourly) {
    throw new Error("Failed to load weather");
  }

  return {
    hourlyUnits,
    times: hourly.time,
    temperatures: hourly.temperature_2m,
    rainChances: hourly.rain,
    showerChances: hourly.showers,
    cloudCovers: hourly.cloud_cover,
    sunshineDuration: hourly.sunshine_duration,
  };
}
