class MlConfig {
  // Ngrok public tunnel
  static const baseUrl = 'https://cross-groovy-frostily.ngrok-free.dev';

  // Headers potrebni za ngrok (preskace browser warning stranicu)
  static const headers = {
    'ngrok-skip-browser-warning': 'true',
    'Content-Type': 'application/json',
  };
}
