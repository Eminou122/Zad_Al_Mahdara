{{flutter_js}}
{{flutter_build_config}}

(function () {
  const lifecycle = window.ZadBootstrap.create(document.getElementById('boot-loader'));

  try {
    _flutter.loader.load({
      serviceWorkerSettings: {
        serviceWorkerVersion: {{flutter_service_worker_version}}
      },
      onEntrypointLoaded: async (engineInitializer) => {
        await lifecycle.run(async () => {
          const appRunner = await engineInitializer.initializeEngine();
          await appRunner.runApp();
        });
      },
    });
  } catch (_) {
    lifecycle.fail();
  }
})();
