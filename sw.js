// ホーム画面に追加できるようにするための最小のService Worker。
// 画面（index.html）は常にネットワークから取るので、更新が古いまま残ることはない。
self.addEventListener('install', () => self.skipWaiting());
self.addEventListener('activate', (e) => e.waitUntil(self.clients.claim()));
self.addEventListener('fetch', () => {});
