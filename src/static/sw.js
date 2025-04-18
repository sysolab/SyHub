/**
 * Plantomio Service Worker
 * Optimized for performance on resource-constrained systems
 */

const CACHE_NAME = 'plantomio-cache-v1';

// Resources to cache immediately
const CRITICAL_ASSETS = [
  '/',
  '/static/css/styles.css',
  '/static/js/main.js',
  '/static/images/icon-192.png',
  '/static/manifest.json'
];

// Resources to cache as they're requested
const CACHE_EXTENSIONS = [
  '.html',
  '.css',
  '.js',
  '.json',
  '.png',
  '.jpg',
  '.svg',
  '.ico'
];

// Maximum age for cached API responses
const API_CACHE_DURATION = {
  '/api/latest': 30 * 1000, // 30 seconds
  '/data/': 5 * 60 * 1000,  // 5 minutes
  '/api/system/info': 60 * 1000 // 1 minute
};

// Install event - cache critical resources
self.addEventListener('install', event => {
  event.waitUntil(
    caches.open(CACHE_NAME)
      .then(cache => {
        // Cache critical assets immediately
        return cache.addAll(CRITICAL_ASSETS);
      })
      .then(() => {
        // Skip waiting to activate immediately
        return self.skipWaiting();
      })
  );
});

// Activate event - clean up old caches and take control
self.addEventListener('activate', event => {
  event.waitUntil(
    Promise.all([
      // Clean up old caches
      caches.keys().then(cacheNames => {
        return Promise.all(
          cacheNames.map(cacheName => {
            if (cacheName !== CACHE_NAME) {
              return caches.delete(cacheName);
            }
          })
        );
      }),
      // Take control of all clients
      self.clients.claim()
    ])
  );
});

// Fetch event - intelligent caching strategy based on request type
self.addEventListener('fetch', event => {
  const url = new URL(event.request.url);
  
  // Handle API requests
  if (url.pathname.startsWith('/api/') || url.pathname.startsWith('/data/')) {
    event.respondWith(handleApiRequest(event.request));
    return;
  }
  
  // Handle static assets
  if (isStaticAsset(url.pathname)) {
    event.respondWith(handleStaticAsset(event.request));
    return;
  }
  
  // Default strategy for all other requests
  event.respondWith(
    caches.match(event.request)
      .then(cachedResponse => {
        if (cachedResponse) {
          // Return cached response
          return cachedResponse;
        }
        
        // Not in cache, fetch from network
        return fetch(event.request)
          .then(response => {
            // Check if we should cache this response
            if (shouldCacheResponse(event.request, response)) {
              return cacheResponse(event.request, response);
            }
            
            return response;
          })
          .catch(error => {
            // Network error, try to return something helpful
            if (event.request.headers.get('accept').includes('text/html')) {
              return caches.match('/');
            }
            
            return new Response(JSON.stringify({
              error: 'Network error',
              offline: true
            }), {
              headers: {'Content-Type': 'application/json'}
            });
          });
      })
  );
});

/**
 * Handle API requests with network-first strategy and timed caching
 * @param {Request} request - The fetch request
 * @returns {Promise<Response>} Response
 */
async function handleApiRequest(request) {
  const url = new URL(request.url);
  const cacheKey = getCacheKeyForApiRequest(request);
  
  try {
    // Try to fetch from network first
    const networkResponse = await fetch(request);
    
    // Cache successful responses
    if (networkResponse.status === 200) {
      await cacheApiResponse(cacheKey, networkResponse.clone());
    }
    
    return networkResponse;
  } catch (error) {
    // Network failed, try cache
    const cachedResponse = await caches.match(cacheKey);
    
    if (cachedResponse) {
      // Check if the cached response is still valid
      const cachedData = await cachedResponse.json();
      
      if (cachedData.timestamp) {
        const age = Date.now() - cachedData.timestamp;
        let maxAge = 5 * 60 * 1000; // Default 5 minutes
        
        // Get appropriate max age for this endpoint
        Object.keys(API_CACHE_DURATION).forEach(key => {
          if (url.pathname.startsWith(key)) {
            maxAge = API_CACHE_DURATION[key];
          }
        });
        
        // If cache is valid, return it
        if (age < maxAge) {
          return new Response(JSON.stringify(cachedData.data), {
            headers: {'Content-Type': 'application/json'}
          });
        }
      }
    }
    
    // No valid cache, return offline response
    return new Response(JSON.stringify({
      error: 'You are offline',
      offline: true,
      timestamp: Date.now()
    }), {
      headers: {'Content-Type': 'application/json'}
    });
  }
}

/**
 * Handle static assets with cache-first strategy
 * @param {Request} request - The fetch request
 * @returns {Promise<Response>} Response
 */
async function handleStaticAsset(request) {
  // Try cache first
  const cachedResponse = await caches.match(request);
  
  if (cachedResponse) {
    return cachedResponse;
  }
  
  // Not in cache, fetch from network
  try {
    const networkResponse = await fetch(request);
    
    // Cache the response if valid
    if (networkResponse.status === 200) {
      const responseToCache = networkResponse.clone();
      caches.open(CACHE_NAME).then(cache => {
        cache.put(request, responseToCache);
      });
    }
    
    return networkResponse;
  } catch (error) {
    // Network error, try to return a fallback
    const url = new URL(request.url);
    const extension = url.pathname.split('.').pop();
    
    if (extension === 'css') {
      return new Response('/* Offline fallback CSS */');
    }
    
    if (extension === 'js') {
      return new Response('console.log("Offline fallback JS");');
    }
    
    if (['png', 'jpg', 'jpeg', 'gif', 'svg'].includes(extension)) {
      // Return transparent 1x1 pixel for images
      return new Response(new Blob());
    }
    
    // Default fallback
    return new Response('Offline');
  }
}

/**
 * Cache API response with timestamp
 * @param {string} cacheKey - Cache key
 * @param {Response} response - Response to cache
 */
async function cacheApiResponse(cacheKey, response) {
  const cache = await caches.open(CACHE_NAME);
  const data = await response.json();
  
  // Add timestamp to the data
  const cachedData = {
    data,
    timestamp: Date.now()
  };
  
  // Create a new response with the timestamped data
  const cachedResponse = new Response(JSON.stringify(cachedData), {
    headers: {'Content-Type': 'application/json'}
  });
  
  // Store in cache
  await cache.put(cacheKey, cachedResponse);
}

/**
 * Get a consistent cache key for API requests
 * @param {Request} request - The fetch request
 * @returns {string} Cache key
 */
function getCacheKeyForApiRequest(request) {
  const url = new URL(request.url);
  
  // For API endpoints, use pathname as cache key to avoid query string variations
  return url.origin + url.pathname;
}

/**
 * Check if the path is for a static asset
 * @param {string} pathname - URL pathname
 * @returns {boolean} True if static asset
 */
function isStaticAsset(pathname) {
  // Check file extension
  const extension = pathname.split('.').pop().toLowerCase();
  return CACHE_EXTENSIONS.includes('.' + extension) || pathname.startsWith('/static/');
}

/**
 * Determine if a response should be cached
 * @param {Request} request - The fetch request
 * @param {Response} response - The fetch response
 * @returns {boolean} True if response should be cached
 */
function shouldCacheResponse(request, response) {
  // Only cache successful responses
  if (!response || response.status !== 200) {
    return false;
  }
  
  // Cache GET requests
  if (request.method !== 'GET') {
    return false;
  }
  
  // Check content type
  const contentType = response.headers.get('content-type');
  
  if (contentType) {
    // Cache common static asset types
    if (
      contentType.includes('text/html') ||
      contentType.includes('text/css') ||
      contentType.includes('application/javascript') ||
      contentType.includes('image/') ||
      contentType.includes('font/') ||
      contentType.includes('application/json')
    ) {
      return true;
    }
  }
  
  // Check URL pattern
  const url = new URL(request.url);
  
  // Cache static assets
  if (isStaticAsset(url.pathname)) {
    return true;
  }
  
  return false;
}

/**
 * Cache a response
 * @param {Request} request - The fetch request
 * @param {Response} response - The response to cache
 * @returns {Response} The original response
 */
async function cacheResponse(request, response) {
  const responseToCache = response.clone();
  const cache = await caches.open(CACHE_NAME);
  await cache.put(request, responseToCache);
  return response;
}

// Background sync for offline data submission
self.addEventListener('sync', event => {
  if (event.tag === 'sync-sensor-data') {
    event.waitUntil(
      // Process any pending sensor data
      self.clients.matchAll().then(clients => {
        clients.forEach(client => {
          client.postMessage({
            type: 'BACKGROUND_SYNC',
            message: 'Syncing data in background'
          });
        });
      })
    );
  }
});

// Push notification handler
self.addEventListener('push', event => {
  const data = event.data.json();
  
  const options = {
    body: data.message || 'New update from Plantomio',
    icon: '/static/images/icon-192.png',
    badge: '/static/images/icon-192.png',
    data: {
      url: data.url || '/'
    }
  };
  
  event.waitUntil(
    self.registration.showNotification('Plantomio Alert', options)
  );
});

// Notification click handler
self.addEventListener('notificationclick', event => {
  event.notification.close();
  
  event.waitUntil(
    clients.matchAll({type: 'window'}).then(windowClients => {
      // Check if there is already a window with our URL open
      for (const client of windowClients) {
        if (client.url === event.notification.data.url && 'focus' in client) {
          return client.focus();
        }
      }
      
      // If not, open a new window
      if (clients.openWindow) {
        return clients.openWindow(event.notification.data.url);
      }
    })
  );
});