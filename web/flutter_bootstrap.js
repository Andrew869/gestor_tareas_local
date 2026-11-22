{{flutter_js}}
{{flutter_build_config}}

// Only the release packaging step enables the offline worker.
const offlineEnabled = false;
if (offlineEnabled && 'serviceWorker' in navigator) {
  const status = document.getElementById('offline-status');
  status.hidden = false;
  status.textContent = 'Preparando acceso sin conexion...';
  navigator.serviceWorker.register(new URL('offline_worker.js', document.baseURI), {
    updateViaCache: 'none',
  }).then(async () => {
    const timeout = setTimeout(() => {
      status.textContent = 'No se pudo preparar el acceso sin conexion. Reabre con conexion.';
    }, 90000);
    await navigator.serviceWorker.ready;
    clearTimeout(timeout);
    document.documentElement.dataset.offline = 'ready';
    status.textContent = 'Disponible sin conexion';
  }).catch(() => {
    status.textContent = 'No se pudo preparar el acceso sin conexion. Reabre con conexion.';
  });
}

_flutter.loader.load({
  config: {
    canvasKitBaseUrl: new URL('canvaskit/', document.baseURI).href,
    fontFallbackBaseUrl: new URL('fonts/', document.baseURI).href,
  },
});
