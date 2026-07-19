(function () {
  window.ZadBootstrap = {
    create(loader, reloadPage = () => window.location.reload()) {
      let failed = false;
      let frame = 0;
      const timeout = setTimeout(fail, 10000);

      function fail() {
        if (failed) return;
        failed = true;
        clearTimeout(timeout);
        cancelAnimationFrame(frame);
        if (!loader) return;
        console.error('ZAD_BOOTSTRAP_FAILED');
        loader.replaceChildren();
        const message = document.createElement('p');
        message.textContent = 'تعذر تشغيل التطبيق. يرجى تحديث الصفحة.';
        const retry = document.createElement('button');
        retry.type = 'button';
        retry.textContent = 'إعادة المحاولة';
        retry.addEventListener('click', reloadPage, { once: true });
        loader.append(message, retry);
      }

      function ready() {
        if (failed) return;
        const pane = document.querySelector('flt-glass-pane');
        const canvas = document.querySelector('canvas') || pane?.shadowRoot?.querySelector('canvas');
        if (canvas && canvas.width > 0 && canvas.height > 0) {
          clearTimeout(timeout);
          loader?.remove();
          return;
        }
        frame = requestAnimationFrame(ready);
      }

      return {
        async run(runApp) {
          try {
            await runApp();
            frame = requestAnimationFrame(ready);
          } catch (_) {
            fail();
          }
        },
        fail,
      };
    },
  };
})();
