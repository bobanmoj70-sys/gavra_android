class MlConfig {
  // Lokalna IP adresa laptopa na Tailscale VPN mreži kako bi i telefon i emulator imali pristup
  static const baseUrl = 'http://100.79.160.71:8000';

  static const headers = {
    'Content-Type': 'application/json',
  };
}
