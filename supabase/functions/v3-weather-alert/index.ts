// @ts-nocheck
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

type GradConfig = { code: string; lat: number; lng: number; name: string };

const GRADOVI: GradConfig[] = [
  { code: "BC", lat: 44.8973, lng: 21.4177, name: "Bela Crkva" },
  { code: "VS", lat: 45.119, lng: 21.303, name: "Vršac" },
];

type DangerAlert = {
  conditionCode: string;
  severity: "info" | "warning" | "danger";
  title_sr: string;
  body_sr: string;
  title_en: string;
  body_en: string;
  title_ru: string;
  body_ru: string;
  title_de: string;
  body_de: string;
  title_zh: string;
  body_zh: string;
};

const SNOW_CODES = new Set([71, 73, 75, 77, 85, 86]);
const FOG_CODES = new Set([45, 48]);
const DRIZZLE_CODES = new Set([51, 53, 55, 56, 57]);
const RAIN_CODES = new Set([61, 63, 65, 66, 67, 80, 81, 82]);
const HEAVY_RAIN_CODES = new Set([65, 67, 82]);
const STORM_CODES = new Set([95, 96, 99]);

function detectAlerts(weatherCode: number, tempC: number, grad: string): DangerAlert[] {
  const alerts: DangerAlert[] = [];

  // Sneg / poledica
  if (SNOW_CODES.has(weatherCode)) {
    alerts.push({
      conditionCode: "snow_ice",
      severity: "danger",
      title_sr: `❄️ Upozorenje: sneg (${grad})`,
      body_sr: "Sneg i moguća poledica na putu. Vozite izuzetno oprezno, smanjite brzinu.",
      title_en: `❄️ Warning: snow (${grad})`,
      body_en: "Snow and possible icy roads. Drive extremely carefully, reduce speed.",
      title_ru: `❄️ Предупреждение: снег (${grad})`,
      body_ru: "Снег и возможная гололедица на дороге. Будьте предельно осторожны.",
      title_de: `❄️ Warnung: Schnee (${grad})`,
      body_de: "Schnee und mögliches Glatteis. Fahren Sie äußerst vorsichtig.",
      title_zh: `❄️ 警告：降雪 (${grad})`,
      body_zh: "降雪且路面可能结冰。请极其小心驾驶，降低车速。",
    });
  } else if (RAIN_CODES.has(weatherCode) && tempC <= 2) {
    // Kiša na temperaturi blizu nule -> rizik od poledice (freezing rain risk)
    alerts.push({
      conditionCode: "icy_risk",
      severity: "danger",
      title_sr: `🧊 Upozorenje: rizik od poledice (${grad})`,
      body_sr: "Kiša pri niskoj temperaturi - moguća poledica na kolovozu. Vozite oprezno.",
      title_en: `🧊 Warning: icy road risk (${grad})`,
      body_en: "Rain at near-freezing temperature - possible icy road. Drive carefully.",
      title_ru: `🧊 Предупреждение: риск гололеда (${grad})`,
      body_ru: "Дождь при околонулевой температуре - возможен гололёд. Будьте осторожны.",
      title_de: `🧊 Warnung: Glatteisgefahr (${grad})`,
      body_de: "Regen bei Temperaturen um den Gefrierpunkt - mögliches Glatteis.",
      title_zh: `🧊 警告：结冰风险 (${grad})`,
      body_zh: "接近冰点的降雨 - 路面可能结冰。请小心驾驶。",
    });
  }

  // Magla
  if (FOG_CODES.has(weatherCode)) {
    alerts.push({
      conditionCode: "fog",
      severity: "warning",
      title_sr: `🌫️ Upozorenje: magla (${grad})`,
      body_sr: "Smanjena vidljivost zbog magle. Uključite svetla, vozite sporije.",
      title_en: `🌫️ Warning: fog (${grad})`,
      body_en: "Reduced visibility due to fog. Turn on lights, drive slower.",
      title_ru: `🌫️ Предупреждение: туман (${grad})`,
      body_ru: "Пониженная видимость из-за тумана. Включите фары, снизьте скорость.",
      title_de: `🌫️ Warnung: Nebel (${grad})`,
      body_de: "Eingeschränkte Sicht durch Nebel. Licht einschalten, langsamer fahren.",
      title_zh: `🌫️ 警告：雾 (${grad})`,
      body_zh: "雾导致能见度降低。请开启车灯，减速行驶。",
    });
  }

  // Oluja / grmljavina
  if (STORM_CODES.has(weatherCode)) {
    alerts.push({
      conditionCode: "storm",
      severity: "danger",
      title_sr: `⛈️ Upozorenje: oluja (${grad})`,
      body_sr: "Grmljavinska oluja u toku. Vozite oprezno, moguć jak vetar i pljusak.",
      title_en: `⛈️ Warning: storm (${grad})`,
      body_en: "Thunderstorm in progress. Drive carefully, possible strong wind and downpour.",
      title_ru: `⛈️ Предупреждение: гроза (${grad})`,
      body_ru: "Гроза в разгаре. Будьте осторожны, возможен сильный ветер и ливень.",
      title_de: `⛈️ Warnung: Gewitter (${grad})`,
      body_de: "Gewitter im Gange. Vorsicht, möglicher starker Wind und Regenguss.",
      title_zh: `⛈️ 警告：暴风雨 (${grad})`,
      body_zh: "雷暴天气进行中。请小心驾驶，可能有强风和暴雨。",
    });
  } else if (HEAVY_RAIN_CODES.has(weatherCode)) {
    // Jaka kiša (bez grmljavine) -> rizik od aquaplaninga / klizanja
    alerts.push({
      conditionCode: "heavy_rain",
      severity: "warning",
      title_sr: `🌧️ Upozorenje: jaka kiša (${grad})`,
      body_sr: "Jaka kiša - rizik od klizanja i aquaplaninga. Smanjite brzinu.",
      title_en: `🌧️ Warning: heavy rain (${grad})`,
      body_en: "Heavy rain - risk of skidding and aquaplaning. Reduce speed.",
      title_ru: `🌧️ Предупреждение: сильный дождь (${grad})`,
      body_ru: "Сильный дождь - риск заноса и аквапланирования. Снизьте скорость.",
      title_de: `🌧️ Warnung: starker Regen (${grad})`,
      body_de: "Starker Regen - Rutsch- und Aquaplaninggefahr. Geschwindigkeit reduzieren.",
      title_zh: `🌧️ 警告：大雨 (${grad})`,
      body_zh: "大雨 - 有打滑和水滑风险。请减速行驶。",
    });
  }

  // Ekstremna vrucina
  if (tempC >= 35) {
    alerts.push({
      conditionCode: "extreme_heat",
      severity: "warning",
      title_sr: `☀️ Upozorenje: ekstremna vrućina (${grad})`,
      body_sr: `Temperatura ${Math.round(tempC)}°C. Pijte dovoljno tečnosti, izbegavajte pregrevanje vozila.`,
      title_en: `☀️ Warning: extreme heat (${grad})`,
      body_en: `Temperature ${Math.round(tempC)}°C. Stay hydrated, avoid vehicle overheating.`,
      title_ru: `☀️ Предупреждение: сильная жара (${grad})`,
      body_ru: `Температура ${Math.round(tempC)}°C. Пейте больше воды, избегайте перегрева авто.`,
      title_de: `☀️ Warnung: extreme Hitze (${grad})`,
      body_de: `Temperatur ${Math.round(tempC)}°C. Ausreichend trinken, Fahrzeugüberhitzung vermeiden.`,
      title_zh: `☀️ 警告：极端高温 (${grad})`,
      body_zh: `温度 ${Math.round(tempC)}°C。请多喝水，避免车辆过热。`,
    });
  }

  return alerts;
}

Deno.serve(async (_req: Request) => {
  const supabaseUrl = Deno.env.get("SUPABASE_URL") ?? "";
  const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";

  if (!supabaseUrl || !serviceRoleKey) {
    return new Response(JSON.stringify({ ok: false, error: "Missing Supabase env" }), {
      status: 500,
      headers: { "Content-Type": "application/json" },
    });
  }

  const client = createClient(supabaseUrl, serviceRoleKey, {
    auth: { persistSession: false, autoRefreshToken: false },
  });

  const results: Record<string, unknown>[] = [];

  for (const grad of GRADOVI) {
    try {
      const url = new URL("https://api.open-meteo.com/v1/forecast");
      url.searchParams.set("latitude", String(grad.lat));
      url.searchParams.set("longitude", String(grad.lng));
      url.searchParams.set("timezone", "Europe/Belgrade");
      url.searchParams.set("current", "temperature_2m,weather_code");

      const response = await fetch(url.toString());
      if (!response.ok) {
        results.push({ grad: grad.code, ok: false, error: `status ${response.status}` });
        continue;
      }

      const data = await response.json();
      const current = data?.current;
      const tempC = Number(current?.temperature_2m);
      const weatherCode = Number(current?.weather_code);

      if (!Number.isFinite(tempC) || !Number.isFinite(weatherCode)) {
        results.push({ grad: grad.code, ok: false, error: "invalid current data" });
        continue;
      }

      const alerts = detectAlerts(weatherCode, tempC, grad.name);

      for (const alert of alerts) {
        const { data: rpcData, error: rpcError } = await client.rpc("v3_notify_vozaci_weather_alert", {
          p_grad: grad.code,
          p_condition_code: alert.conditionCode,
          p_severity: alert.severity,
          p_title_sr: alert.title_sr,
          p_body_sr: alert.body_sr,
          p_title_en: alert.title_en,
          p_body_en: alert.body_en,
          p_title_ru: alert.title_ru,
          p_body_ru: alert.body_ru,
          p_title_de: alert.title_de,
          p_body_de: alert.body_de,
          p_title_zh: alert.title_zh,
          p_body_zh: alert.body_zh,
        });

        results.push({
          grad: grad.code,
          condition: alert.conditionCode,
          ok: !rpcError,
          error: rpcError?.message,
          data: rpcData,
        });
      }

      if (alerts.length === 0) {
        results.push({ grad: grad.code, ok: true, alerts: 0 });
      }
    } catch (e) {
      results.push({ grad: grad.code, ok: false, error: e instanceof Error ? e.message : String(e) });
    }
  }

  return new Response(JSON.stringify({ ok: true, results }), {
    status: 200,
    headers: { "Content-Type": "application/json" },
  });
});
