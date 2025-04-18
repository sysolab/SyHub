/**
 * Update system status UI
 * @param {Object} data - System status data
 */
function updateSystemStatus(data) {
    if (!data) return;
    
    // Update CPU usage
    if (data.cpu) {
        if (elements.cpuGauge) elements.cpuGauge.style.width = `${data.cpu.percent}%`;
        if (elements.cpuValue) elements.cpuValue.textContent = `${data.cpu.percent}%`;
        if (elements.cpuCores) elements.cpuCores.textContent = `${data.cpu.cores} cores`;
    }
    
    // Update memory usage
    if (data.memory) {
        if (elements.memoryGauge) elements.memoryGauge.style.width = `${data.memory.percent}%`;
        if (elements.memoryValue) elements.memoryValue.textContent = `${data.memory.percent}%`;
    }
    
    // Update disk usage
    if (data.disk) {
        if (elements.diskGauge) elements.diskGauge.style.width = `${data.disk.percent}%`;
        if (elements.diskValue) elements.diskValue.textContent = `${data.disk.percent}%`;
    }
    
    // Update network usage
    if (data.network) {
        if (elements.networkGauge) elements.networkGauge.style.width = `${data.network.percent}%`;
        if (elements.networkValue) elements.networkValue.textContent = `${data.network.percent}%`;
    }
    
    // Update other system info if available
    if (data.uptime) {
        const uptimeElement = document.getElementById('uptime');
        if (uptimeElement) uptimeElement.textContent = data.uptime;
    }
    
    if (data.lastBoot) {
        const lastBootElement = document.getElementById('last-boot');
        if (lastBootElement) lastBootElement.textContent = data.lastBoot;
    }
    
    if (data.os) {
        const osInfoElement = document.getElementById('os-info');
        if (osInfoElement) osInfoElement.textContent = data.os;
    }
}

// ======== Chart Management ========

/**
 * Initialize all charts (but don't render them yet for performance)
 */
function initializeCharts() {
    // Define chart options once for all charts for better performance
    const commonOptions = {
        responsive: true,
        maintainAspectRatio: false,
        animation: {
            duration: 0 // Disable animations for better performance
        },
        plugins: {
            legend: {
                display: false
            },
            tooltip: {
                enabled: true,
                mode: 'index',
                intersect: false,
                backgroundColor: 'rgba(255, 255, 255, 0.9)',
                titleColor: '#1F2937',
                bodyColor: '#1F2937',
                borderColor: '#E5E7EB',
                borderWidth: 1,
                padding: 10,
                cornerRadius: 4,
                boxShadow: '0 4px 6px -1px rgba(0, 0, 0, 0.1), 0 2px 4px -1px rgba(0, 0, 0, 0.06)',
                callbacks: {
                    label: function(context) {
                        let label = context.dataset.label || '';
                        if (label) {
                            label += ': ';
                        }
                        if (context.parsed.y !== null) {
                            label += context.parsed.y.toFixed(1);
                        }
                        return label;
                    }
                }
            }
        },
        scales: {
            x: {
                type: 'time',
                time: {
                    unit: 'hour',
                    displayFormats: {
                        hour: 'HH:mm'
                    }
                },
                grid: {
                    display: false
                }
            },
            y: {
                beginAtZero: false,
                grid: {
                    color: 'rgba(156, 163, 175, 0.1)'
                },
                ticks: {
                    padding: 10
                }
            }
        },
        elements: {
            line: {
                tension: 0.3
            },
            point: {
                radius: 0, // Hide points for better performance
                hitRadius: 10,
                hoverRadius: 5
            }
        }
    };
    
    // Define chart configurations
    const chartConfigs = {
        'ph-chart': {
            type: 'line',
            options: {
                ...JSON.parse(JSON.stringify(commonOptions)),
                scales: {
                    ...JSON.parse(JSON.stringify(commonOptions.scales)),
                    y: {
                        ...JSON.parse(JSON.stringify(commonOptions.scales.y)),
                        min: 4,
                        max: 9,
                        ticks: {
                            stepSize: 0.5
                        }
                    }
                }
            },
            data: {
                datasets: [{
                    label: 'pH',
                    borderColor: '#8B5CF6',
                    backgroundColor: 'rgba(139, 92, 246, 0.1)',
                    borderWidth: 2,
                    fill: true,
                    data: []
                }]
            }
        },
        'ec-chart': {
            type: 'line',
            options: {
                ...JSON.parse(JSON.stringify(commonOptions)),
                scales: {
                    ...JSON.parse(JSON.stringify(commonOptions.scales)),
                    y: {
                        ...JSON.parse(JSON.stringify(commonOptions.scales.y)),
                        min: 0,
                        ticks: {
                            callback: function(value) {
                                return value + 'μS/cm';
                            }
                        }
                    }
                }
            },
            data: {
                datasets: [{
                    label: 'EC',
                    borderColor: '#10B981',
                    backgroundColor: 'rgba(16, 185, 129, 0.1)',
                    borderWidth: 2,
                    fill: true,
                    data: []
                }]
            }
        },
        'temperature-chart': {
            type: 'line',
            options: {
                ...JSON.parse(JSON.stringify(commonOptions)),
                scales: {
                    ...JSON.parse(JSON.stringify(commonOptions.scales)),
                    y: {
                        ...JSON.parse(JSON.stringify(commonOptions.scales.y)),
                        ticks: {
                            callback: function(value) {
                                return value + '°C';
                            }
                        }
                    }
                }
            },
            data: {
                datasets: [{
                    label: 'Temperature',
                    borderColor: '#F59E0B',
                    backgroundColor: 'rgba(245, 158, 11, 0.1)',
                    borderWidth: 2,
                    fill: true,
                    data: []
                }]
            }
        },
        'orp-chart': {
            type: 'line',
            options: {
                ...JSON.parse(JSON.stringify(commonOptions)),
                scales: {
                    ...JSON.parse(JSON.stringify(commonOptions.scales)),
                    y: {
                        ...JSON.parse(JSON.stringify(commonOptions.scales.y)),
                        min: 0,
                        ticks: {
                            callback: function(value) {
                                return value + 'mV';
                            }
                        }
                    }
                }
            },
            data: {
                datasets: [{
                    label: 'ORP',
                    borderColor: '#3B82F6',
                    backgroundColor: 'rgba(59, 130, 246, 0.1)',
                    borderWidth: 2,
                    fill: true,
                    data: []
                }]
            }
        },
        'tds-chart': {
            type: 'line',
            options: {
                ...JSON.parse(JSON.stringify(commonOptions)),
                scales: {
                    ...JSON.parse(JSON.stringify(commonOptions.scales)),
                    y: {
                        ...JSON.parse(JSON.stringify(commonOptions.scales.y)),
                        min: 0,
                        ticks: {
                            callback: function(value) {
                                return value + 'ppm';
                            }
                        }
                    }
                }
            },
            data: {
                datasets: [{
                    label: 'TDS',
                    borderColor: '#EF4444',
                    backgroundColor: 'rgba(239, 68, 68, 0.1)',
                    borderWidth: 2,
                    fill: true,
                    data: []
                }]
            }
        },
        'distance-chart': {
            type: 'line',
            options: {
                ...JSON.parse(JSON.stringify(commonOptions)),
                scales: {
                    ...JSON.parse(JSON.stringify(commonOptions.scales)),
                    y: {
                        ...JSON.parse(JSON.stringify(commonOptions.scales.y)),
                        reverse: true, // Reverse the scale for water level
                        ticks: {
                            callback: function(value) {
                                return value + 'cm';
                            }
                        }
                    }
                }
            },
            data: {
                datasets: [{
                    label: 'Water Level',
                    borderColor: '#60A5FA',
                    backgroundColor: 'rgba(96, 165, 250, 0.1)',
                    borderWidth: 2,
                    fill: true,
                    data: []
                }]
            }
        }
    };
    
    // Store chart configs in state for later use
    state.chartConfigs = chartConfigs;
}

/**
 * Render charts when the charts tab is active
 */
function renderCharts() {
    // Check if we have already rendered the charts
    if (Object.keys(state.charts).length > 0) {
        // Just update the data instead of re-rendering
        updateCharts();
        return;
    }
    
    // Create charts for each configured element
    Object.keys(state.chartConfigs).forEach(chartId => {
        const chartElement = document.getElementById(chartId);
        if (!chartElement) return;
        
        const config = state.chartConfigs[chartId];
        
        // Create the chart
        const chart = new Chart(chartElement, {
            type: config.type,
            data: config.data,
            options: config.options
        });
        
        // Store the chart instance
        state.charts[chartId] = chart;
    });
    
    // Update charts with data
    updateCharts();
}

/**
 * Update chart data with latest time series data
 */
function updateCharts() {
    // Check if we have time series data
    if (!state.timeSeriesData || Object.keys(state.timeSeriesData).length === 0) {
        // Try to fetch time series data
        fetchTimeSeriesData();
        return;
    }
    
    // Get time range based on settings
    const now = new Date();
    let fromTime;
    
    switch (config.chartTimeRange) {
        case 'week':
            fromTime = new Date(now.getTime() - 7 * 24 * 60 * 60 * 1000);
            break;
        case 'month':
            fromTime = new Date(now.getTime() - 30 * 24 * 60 * 60 * 1000);
            break;
        case 'day':
        default:
            fromTime = new Date(now.getTime() - 24 * 60 * 60 * 1000);
            break;
    }
    
    // Update each chart's data
    updateChartData('ph-chart', 'pH', fromTime);
    updateChartData('ec-chart', 'EC', fromTime);
    updateChartData('temperature-chart', 'temperature', fromTime);
    updateChartData('orp-chart', 'ORP', fromTime);
    updateChartData('tds-chart', 'TDS', fromTime);
    updateChartData('distance-chart', 'distance', fromTime);
}

/**
 * Update data for a specific chart
 * @param {string} chartId - Chart element ID
 * @param {string} metric - Metric name
 * @param {Date} fromTime - Start time for data
 */
function updateChartData(chartId, metric, fromTime) {
    const chart = state.charts[chartId];
    if (!chart) return;
    
    const timeSeriesData = state.timeSeriesData[metric];
    if (!timeSeriesData || timeSeriesData.length === 0) return;
    
    // Filter data by time range
    const filteredData = timeSeriesData.filter(item => {
        return new Date(item.time * 1000) >= fromTime;
    });
    
    // Convert to chart.js format
    const chartData = filteredData.map(item => ({
        x: new Date(item.time * 1000),
        y: item.value
    }));
    
    // Update chart data
    chart.data.datasets[0].data = chartData;
    
    // Update chart
    chart.update('none'); // Use 'none' mode for better performance
}

/**
 * Fetch time series data for charts
 */
async function fetchTimeSeriesData() {
    try {
        // First check if we already have data in state
        if (state.data && state.data.timeSeriesData && Object.keys(state.data.timeSeriesData).length > 0) {
            state.timeSeriesData = state.data.timeSeriesData;
            updateCharts();
            return;
        }
        
        // Show loading indicator in charts
        const chartContainers = document.querySelectorAll('.chart-container');
        chartContainers.forEach(container => {
            const loadingIndicator = document.createElement('div');
            loadingIndicator.className = 'absolute inset-0 flex items-center justify-center bg-white bg-opacity-80';
            loadingIndicator.innerHTML = '<div class="loading-spinner"></div><span class="ml-2 text-gray-600">Loading data...</span>';
            container.style.position = 'relative';
            container.appendChild(loadingIndicator);
        });
        
        // We need to fetch time series data for each metric
        const metrics = ['temperature', 'pH', 'ORP', 'TDS', 'EC', 'distance'];
        const promises = metrics.map(metric => fetchMetricData(metric));
        
        // Wait for all requests to complete
        await Promise.all(promises);
        
        // Remove loading indicators
        chartContainers.forEach(container => {
            const loadingIndicator = container.querySelector('.absolute');
            if (loadingIndicator) {
                container.removeChild(loadingIndicator);
            }
        });
        
        // Update charts
        updateCharts();
    } catch (error) {
        console.error('Error fetching time series data:', error);
        
        // Show error in charts
        const chartContainers = document.querySelectorAll('.chart-container');
        chartContainers.forEach(container => {
            const errorMessage = document.createElement('div');
            errorMessage.className = 'absolute inset-0 flex items-center justify-center bg-white bg-opacity-80';
            errorMessage.innerHTML = '<span class="text-red-500">Error loading chart data</span>';
            container.style.position = 'relative';
            container.appendChild(errorMessage);
        });
    }
}

/**
 * Fetch time series data for a specific metric
 * @param {string} metric - Metric name
 */
async function fetchMetricData(metric) {
    try {
        const response = await fetch(`/data/${metric}`);
        
        if (!response.ok) {
            throw new Error(`API error: ${response.status}`);
        }
        
        const data = await response.json();
        
        // Save to state
        if (!state.timeSeriesData) {
            state.timeSeriesData = {};
        }
        
        state.timeSeriesData[metric] = data;
    } catch (error) {
        console.error(`Error fetching ${metric} data:`, error);
    }
}

// Start the application when DOM is ready
if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', () => {
        console.log('Initializing Plantomio Dashboard...');
    });
} else {
    console.log('Initializing Plantomio Dashboard...');
}

// Add mock data for debugging if API is not available
if (config.debug) {
    setTimeout(() => {
        const mockData = {
            temperature: { value: 22.5, time: Date.now() / 1000 },
            pH: { value: 6.2, time: Date.now() / 1000 },
            ORP: { value: 350, time: Date.now() / 1000 },
            TDS: { value: 250, time: Date.now() / 1000 },
            EC: { value: 15, time: Date.now() / 1000 },
            distance: { value: 5, time: Date.now() / 1000 },
            deviceID: 'PI-Debug'
        };
        updateDashboard(mockData);
        
        // Log simulated activity
        logActivity('Debug', 'Simulated data loaded for testing');
    }, 1000);
}.y)),
                        min: 4,
                        max: 9,
                        ticks: {
                            stepSize: 0.5
                        }
                    }
                }
            },
            data: {
                datasets: [{
                    label: 'pH',
                    borderColor: '#8B5CF6',
                    backgroundColor: 'rgba(139, 92, 246, 0.1)',
                    borderWidth: 2,
                    fill: true,
                    data: []
                }]
            }
        },
        'ec-chart': {
            type: 'line',
            options: {
                ...JSON.parse(JSON.stringify(commonOptions)),
                scales: {
                    ...JSON.parse(JSON.stringify(commonOptions.scales)),
                    y: {
                        ...JSON.parse(JSON.stringify(commonOptions.scales/**
 * Plantomio Dashboard - Main JavaScript
 * 
 * Optimized for resource-constrained systems like Raspberry Pi 3B
 * Features:
 * - Efficient data fetching with ETag support and caching
 * - WebSocket fallback with long-polling
 * - Responsive design with theme support
 * - Offline capability with service worker integration
 * - Optimized for low memory usage
 */

// Configuration and state management
const config = {
    refreshInterval: 30000,  // Default refresh interval in ms
    tankMinDistance: 2,      // Minimum distance for tank (100% full)
    tankMaxDistance: 20,     // Maximum distance for tank (0% full)
    temperatureUnit: 'celsius', // Default temperature unit
    theme: 'green',          // Default theme
    chartTimeRange: 'day',   // Default chart time range
    debug: false             // Debug mode
};

// Application state
const state = {
    data: null,              // Current sensor data
    timeSeriesData: {},      // Historical time series data
    etag: null,              // Current ETag for caching
    charts: {},              // Chart instances
    lastUpdate: null,        // Last update timestamp
    isOffline: false,        // Offline status
    autoUpdateEnabled: true, // Auto update toggle
    updateTimer: null,       // Timer reference for updates
    navState: 'dashboard',   // Current navigation state
    activityLog: []          // Activity log entries
};

// DOM Elements - Cached for performance
const elements = {};

// WebSocket connection (will fallback to long polling if unavailable)
let socket = null;

// ======== Initialization ========

/**
 * Initialize the application when DOM is ready
 */
document.addEventListener('DOMContentLoaded', () => {
    // Cache DOM elements for better performance
    cacheElements();
    
    // Load saved settings
    loadSettings();
    
    // Set up event listeners
    setupEventListeners();
    
    // Initialize UI components
    initializeUI();
    
    // Initial data load
    fetchLatestData();
    
    // Set up real-time updates
    setupRealTimeUpdates();
    
    // Check for offline status
    setupOfflineDetection();
    
    // Initialize charts (but don't render until needed)
    initializeCharts();
    
    // Log initialization
    logActivity('System', 'Dashboard initialized');
});

/**
 * Cache DOM elements for better performance
 */
function cacheElements() {
    // Status elements
    elements.connectionStatus = document.getElementById('connection-status');
    elements.deviceId = document.getElementById('device-id');
    elements.lastUpdate = document.getElementById('last-update');
    
    // Navigation
    elements.navLinks = document.querySelectorAll('.nav-link');
    elements.sectionContainers = document.querySelectorAll('.section-container');
    
    // Buttons
    elements.refreshBtn = document.getElementById('refresh-btn');
    elements.toggleAutoUpdateBtn = document.getElementById('toggle-auto-update');
    elements.settingsButton = document.getElementById('settings-button');
    
    // Modals
    elements.settingsModal = document.getElementById('settings-modal');
    elements.closeSettings = document.getElementById('close-settings');
    elements.saveSettings = document.getElementById('save-settings');
    elements.resetSettings = document.getElementById('reset-settings');
    
    // Settings inputs
    elements.refreshRate = document.getElementById('refresh-rate');
    elements.tankMin = document.getElementById('tank-min');
    elements.tankMax = document.getElementById('tank-max');
    elements.themeButtons = document.querySelectorAll('.theme-btn');
    elements.temperatureUnitInputs = document.querySelectorAll('input[name="temperature-unit"]');
    
    // Water tank
    elements.waterFill = document.getElementById('water-fill');
    elements.tankLevelPercentage = document.getElementById('tank-level-percentage');
    
    // Alerts
    elements.offlineAlert = document.getElementById('offline-alert');
    
    // Chart tabs
    elements.timeRangeButtons = document.querySelectorAll('.time-range-btn');
    
    // Activity log
    elements.activityLog = document.getElementById('activity-log');
    
    // Value elements - summary
    elements.tempSummary = document.getElementById('temp-summary');
    elements.phSummary = document.getElementById('ph-summary');
    elements.tdsSummary = document.getElementById('tds-summary');
    elements.ecSummary = document.getElementById('ec-summary');
    elements.waterSummary = document.getElementById('water-summary');
    
    // Value elements - detailed
    elements.temperatureValue = document.getElementById('temperature-value');
    elements.phValue = document.getElementById('ph-value');
    elements.orpValue = document.getElementById('orp-value');
    elements.tdsValue = document.getElementById('tds-value');
    elements.ecValue = document.getElementById('ec-value');
    elements.distanceValue = document.getElementById('distance-value');
    
    // Status badges
    elements.tempStatus = document.getElementById('temp-status');
    elements.phStatus = document.getElementById('ph-status');
    elements.tdsStatus = document.getElementById('tds-status');
    elements.ecStatus = document.getElementById('ec-status');
    
    // Gauges
    elements.temperatureGauge = document.getElementById('temperature-gauge');
    elements.phGauge = document.getElementById('ph-gauge');
    elements.orpGauge = document.getElementById('orp-gauge');
    elements.tdsGauge = document.getElementById('tds-gauge');
    elements.ecGauge = document.getElementById('ec-gauge');
    elements.distanceGauge = document.getElementById('distance-gauge');
    
    // System status
    elements.cpuGauge = document.getElementById('cpu-gauge');
    elements.cpuValue = document.getElementById('cpu-value');
    elements.cpuCores = document.getElementById('cpu-cores');
    elements.memoryGauge = document.getElementById('memory-gauge');
    elements.memoryValue = document.getElementById('memory-value');
    elements.diskGauge = document.getElementById('disk-gauge');
    elements.diskValue = document.getElementById('disk-value');
    elements.networkGauge = document.getElementById('network-gauge');
    elements.networkValue = document.getElementById('network-value');
    
    // Health indicators
    elements.healthIndicator = document.getElementById('health-indicator');
    elements.healthStatus = document.getElementById('health-status');
    elements.overallHealthValue = document.getElementById('overall-health-value');
    elements.overallHealthBar = document.getElementById('overall-health-bar');
    elements.waterQualityValue = document.getElementById('water-quality-value');
    elements.waterQualityBar = document.getElementById('water-quality-bar');
    elements.recommendationText = document.getElementById('recommendation-text');
}

/**
 * Load saved settings from localStorage
 */
function loadSettings() {
    try {
        const savedSettings = JSON.parse(localStorage.getItem('plantomio-settings'));
        if (savedSettings) {
            // Merge saved settings with defaults
            Object.assign(config, savedSettings);
            
            // Apply settings to UI
            if (elements.refreshRate) elements.refreshRate.value = config.refreshInterval / 1000;
            if (elements.tankMin) elements.tankMin.value = config.tankMinDistance;
            if (elements.tankMax) elements.tankMax.value = config.tankMaxDistance;
            
            // Apply theme
            applyTheme(config.theme);
            
            // Apply temperature unit
            const tempUnitInput = document.querySelector(`input[name="temperature-unit"][value="${config.temperatureUnit}"]`);
            if (tempUnitInput) tempUnitInput.checked = true;
        }
    } catch (error) {
        console.error('Error loading settings:', error);
        // If error, use defaults
    }
}

/**
 * Set up event listeners for user interactions
 */
function setupEventListeners() {
    // Refresh button
    if (elements.refreshBtn) {
        elements.refreshBtn.addEventListener('click', () => {
            fetchLatestData(true);
            elements.refreshBtn.classList.add('bg-indigo-100');
            setTimeout(() => {
                elements.refreshBtn.classList.remove('bg-indigo-100');
            }, 300);
        });
    }
    
    // Auto update toggle
    if (elements.toggleAutoUpdateBtn) {
        elements.toggleAutoUpdateBtn.addEventListener('click', () => {
            state.autoUpdateEnabled = !state.autoUpdateEnabled;
            updateAutoRefreshUI();
            
            if (state.autoUpdateEnabled) {
                setupAutoRefresh();
                logActivity('System', 'Auto-update enabled');
            } else {
                clearAutoRefresh();
                logActivity('System', 'Auto-update disabled');
            }
        });
    }
    
    // Navigation links
    elements.navLinks.forEach(link => {
        link.addEventListener('click', (e) => {
            const sectionId = link.getAttribute('href')?.substring(1);
            if (sectionId) {
                e.preventDefault();
                navigateTo(sectionId);
            }
        });
    });
    
    // Settings modal
    if (elements.settingsButton) {
        elements.settingsButton.addEventListener('click', () => {
            elements.settingsModal.classList.remove('hidden');
        });
    }
    
    if (elements.closeSettings) {
        elements.closeSettings.addEventListener('click', () => {
            elements.settingsModal.classList.add('hidden');
        });
    }
    
    // Save settings
    if (elements.saveSettings) {
        elements.saveSettings.addEventListener('click', saveUserSettings);
    }
    
    // Reset settings
    if (elements.resetSettings) {
        elements.resetSettings.addEventListener('click', resetUserSettings);
    }
    
    // Theme buttons
    elements.themeButtons.forEach(button => {
        button.addEventListener('click', () => {
            const theme = button.getAttribute('data-theme');
            if (theme) {
                applyTheme(theme);
                config.theme = theme;
                
                // Update UI
                elements.themeButtons.forEach(btn => {
                    btn.classList.remove('border-white');
                    btn.classList.add('border-transparent');
                });
                button.classList.remove('border-transparent');
                button.classList.add('border-white');
            }
        });
    });
    
    // Time range buttons for charts
    elements.timeRangeButtons.forEach(button => {
        button.addEventListener('click', () => {
            const range = button.getAttribute('data-range');
            if (range) {
                config.chartTimeRange = range;
                
                // Update UI
                elements.timeRangeButtons.forEach(btn => {
                    btn.classList.remove('text-gray-900', 'border-b-2', 'border-green-500');
                    btn.classList.add('text-gray-500');
                });
                button.classList.remove('text-gray-500');
                button.classList.add('text-gray-900', 'border-b-2', 'border-green-500');
                
                // Update charts with new range
                updateCharts();
            }
        });
    });
    
    // Close modals when clicking outside
    window.addEventListener('click', (e) => {
        if (e.target === elements.settingsModal) {
            elements.settingsModal.classList.add('hidden');
        }
    });
    
    // Handle keyboard shortcuts
    document.addEventListener('keydown', (e) => {
        // Escape key closes modal
        if (e.key === 'Escape') {
            elements.settingsModal.classList.add('hidden');
        }
        
        // R key to refresh
        if (e.key === 'r' && (e.ctrlKey || e.metaKey)) {
            e.preventDefault();
            fetchLatestData(true);
        }
    });
    
    // Listen for service worker messages
    if (navigator.serviceWorker) {
        navigator.serviceWorker.addEventListener('message', (event) => {
            if (event.data && event.data.type === 'BACKGROUND_SYNC') {
                console.log('Background sync completed');
                fetchLatestData();
            }
        });
    }
    
    // Listen for online/offline events
    window.addEventListener('online', handleOnlineStatus);
    window.addEventListener('offline', handleOfflineStatus);
}

/**
 * Initialize UI components
 */
function initializeUI() {
    // Set initial navigation
    navigateTo('dashboard-section');
    
    // Set up auto-refresh UI
    updateAutoRefreshUI();
    
    // Initialize tank water level
    updateWaterTank(0);
    
    // Apply theme from settings
    applyTheme(config.theme);
}

/**
 * Set up real-time updates (WebSocket with fallback to polling)
 */
function setupRealTimeUpdates() {
    // Try to establish WebSocket connection if supported
    if ('WebSocket' in window) {
        try {
            const protocol = window.location.protocol === 'https:' ? 'wss:' : 'ws:';
            const wsUrl = `${protocol}//${window.location.host}/ws`;
            
            socket = new WebSocket(wsUrl);
            
            socket.onopen = () => {
                console.log('WebSocket connection established');
                elements.connectionStatus.innerHTML = '<span class="pulse mr-1.5"></span>Live Data (WebSocket)';
                state.isOffline = false;
            };
            
            socket.onmessage = (event) => {
                try {
                    const data = JSON.parse(event.data);
                    if (data && !data.error) {
                        updateDashboard(data);
                    }
                } catch (error) {
                    console.error('Error processing WebSocket message:', error);
                }
            };
            
            socket.onclose = () => {
                console.log('WebSocket connection closed, falling back to polling');
                socket = null;
                elements.connectionStatus.innerHTML = '<span class="pulse mr-1.5"></span>Live Data (Polling)';
                // Fall back to polling
                setupAutoRefresh();
            };
            
            socket.onerror = (error) => {
                console.error('WebSocket error:', error);
                socket = null;
                // Fall back to polling
                setupAutoRefresh();
            };
        } catch (error) {
            console.error('Failed to establish WebSocket connection:', error);
            // Fall back to polling
            setupAutoRefresh();
        }
    } else {
        // WebSocket not supported, use polling
        console.log('WebSocket not supported, using polling');
        setupAutoRefresh();
    }
}

/**
 * Set up auto-refresh mechanism for data updates
 */
function setupAutoRefresh() {
    // Clear any existing timer
    clearAutoRefresh();
    
    // Only set up auto-refresh if enabled
    if (state.autoUpdateEnabled) {
        state.updateTimer = setInterval(() => {
            fetchLatestData();
        }, config.refreshInterval);
    }
}

/**
 * Clear auto-refresh timer
 */
function clearAutoRefresh() {
    if (state.updateTimer) {
        clearInterval(state.updateTimer);
        state.updateTimer = null;
    }
}

/**
 * Update auto-refresh UI
 */
function updateAutoRefreshUI() {
    if (elements.toggleAutoUpdateBtn) {
        const statusElement = elements.toggleAutoUpdateBtn.querySelector('.auto-update-status');
        if (statusElement) {
            statusElement.textContent = `Auto Update: ${state.autoUpdateEnabled ? 'ON' : 'OFF'}`;
        }
        
        // Update button style based on state
        if (state.autoUpdateEnabled) {
            elements.toggleAutoUpdateBtn.classList.remove('bg-red-50', 'text-red-700');
            elements.toggleAutoUpdateBtn.classList.add('bg-green-50', 'text-green-700');
        } else {
            elements.toggleAutoUpdateBtn.classList.remove('bg-green-50', 'text-green-700');
            elements.toggleAutoUpdateBtn.classList.add('bg-red-50', 'text-red-700');
        }
    }
}

/**
 * Setup offline detection
 */
function setupOfflineDetection() {
    // Check initial state
    if (!navigator.onLine) {
        handleOfflineStatus();
    }
}

/**
 * Handle online status change
 */
function handleOnlineStatus() {
    state.isOffline = false;
    elements.offlineAlert.classList.add('transform', 'translate-y-16');
    
    setTimeout(() => {
        elements.offlineAlert.classList.add('hidden');
    }, 300);
    
    // Refresh data now that we're back online
    fetchLatestData(true);
    
    logActivity('System', 'Connection restored. Back online.');
}

/**
 * Handle offline status change
 */
function handleOfflineStatus() {
    state.isOffline = true;
    elements.offlineAlert.classList.remove('hidden');
    
    setTimeout(() => {
        elements.offlineAlert.classList.remove('transform', 'translate-y-16');
    }, 10);
    
    logActivity('System', 'Connection lost. Working offline with cached data.');
}

/**
 * Navigate to a section
 * @param {string} sectionId - The section ID to navigate to
 */
function navigateTo(sectionId) {
    // Update navigation state
    state.navState = sectionId;
    
    // Hide all sections
    elements.sectionContainers.forEach(container => {
        container.classList.add('hidden');
    });
    
    // Show the selected section
    const targetSection = document.getElementById(sectionId);
    if (targetSection) {
        targetSection.classList.remove('hidden');
    }
    
    // Update navigation links
    elements.navLinks.forEach(link => {
        link.classList.remove('bg-gray-700');
        link.classList.add('hover:bg-gray-700');
        
        const href = link.getAttribute('href');
        if (href && href === `#${sectionId}`) {
            link.classList.add('bg-gray-700');
            link.classList.remove('hover:bg-gray-700');
        }
    });
    
    // Load section-specific data if needed
    if (sectionId === 'charts-section') {
        // Load chart data and render charts
        renderCharts();
    } else if (sectionId === 'system-status') {
        // Load system status data
        fetchSystemStatus();
    }
}

/**
 * Apply theme to the dashboard
 * @param {string} theme - Theme name
 */
function applyTheme(theme) {
    const root = document.documentElement;
    
    // Reset theme indicators
    elements.themeButtons.forEach(btn => {
        btn.classList.remove('border-white');
        btn.classList.add('border-transparent');
    });
    
    // Apply selected theme
    const themeButton = document.querySelector(`.theme-btn[data-theme="${theme}"]`);
    if (themeButton) {
        themeButton.classList.remove('border-transparent');
        themeButton.classList.add('border-white');
    }
    
    // Apply theme colors
    switch (theme) {
        case 'blue':
            root.style.setProperty('--primary-color', '#3B82F6');
            root.style.setProperty('--secondary-color', '#2563EB');
            break;
        case 'purple':
            root.style.setProperty('--primary-color', '#8B5CF6');
            root.style.setProperty('--secondary-color', '#7C3AED');
            break;
        case 'dark':
            root.style.setProperty('--primary-color', '#6B7280');
            root.style.setProperty('--secondary-color', '#4B5563');
            root.style.setProperty('--sidebar-bg', '#111827');
            break;
        case 'green':
        default:
            root.style.setProperty('--primary-color', '#10B981');
            root.style.setProperty('--secondary-color', '#059669');
            break;
    }
    
    // Save theme preference
    config.theme = theme;
}

/**
 * Save user settings to localStorage
 */
function saveUserSettings() {
    // Update config with form values
    if (elements.refreshRate) {
        config.refreshInterval = parseInt(elements.refreshRate.value, 10) * 1000;
    }
    
    if (elements.tankMin) {
        config.tankMinDistance = parseFloat(elements.tankMin.value);
    }
    
    if (elements.tankMax) {
        config.tankMaxDistance = parseFloat(elements.tankMax.value);
    }
    
    // Get temperature unit
    const selectedTempUnit = document.querySelector('input[name="temperature-unit"]:checked');
    if (selectedTempUnit) {
        config.temperatureUnit = selectedTempUnit.value;
    }
    
    // Save to localStorage
    try {
        localStorage.setItem('plantomio-settings', JSON.stringify(config));
        
        // Show success notification
        const notification = document.createElement('div');
        notification.className = 'fixed bottom-4 right-4 bg-green-500 text-white px-4 py-2 rounded-lg shadow-lg';
        notification.textContent = 'Settings saved successfully';
        document.body.appendChild(notification);
        
        // Remove notification after 3 seconds
        setTimeout(() => {
            document.body.removeChild(notification);
        }, 3000);
        
        // Close settings modal
        elements.settingsModal.classList.add('hidden');
        
        // Apply new settings
        setupAutoRefresh();
        updateDashboard(state.data);
        
        // Log activity
        logActivity('System', 'Settings updated');
    } catch (error) {
        console.error('Error saving settings:', error);
        
        // Show error notification
        const notification = document.createElement('div');
        notification.className = 'fixed bottom-4 right-4 bg-red-500 text-white px-4 py-2 rounded-lg shadow-lg';
        notification.textContent = 'Error saving settings';
        document.body.appendChild(notification);
        
        // Remove notification after 3 seconds
        setTimeout(() => {
            document.body.removeChild(notification);
        }, 3000);
    }
}

/**
 * Reset user settings to defaults
 */
function resetUserSettings() {
    // Confirm reset
    if (!confirm('Reset all settings to defaults?')) {
        return;
    }
    
    // Default config
    const defaultConfig = {
        refreshInterval: 30000,
        tankMinDistance: 2,
        tankMaxDistance: 20,
        temperatureUnit: 'celsius',
        theme: 'green',
        chartTimeRange: 'day'
    };
    
    // Update config
    Object.assign(config, defaultConfig);
    
    // Update UI elements
    if (elements.refreshRate) elements.refreshRate.value = config.refreshInterval / 1000;
    if (elements.tankMin) elements.tankMin.value = config.tankMinDistance;
    if (elements.tankMax) elements.tankMax.value = config.tankMaxDistance;
    
    // Update temperature unit
    const tempUnitInput = document.querySelector(`input[name="temperature-unit"][value="${config.temperatureUnit}"]`);
    if (tempUnitInput) tempUnitInput.checked = true;
    
    // Apply theme
    applyTheme(config.theme);
    
    // Clear localStorage
    localStorage.removeItem('plantomio-settings');
    
    // Show notification
    const notification = document.createElement('div');
    notification.className = 'fixed bottom-4 right-4 bg-blue-500 text-white px-4 py-2 rounded-lg shadow-lg';
    notification.textContent = 'Settings reset to defaults';
    document.body.appendChild(notification);
    
    // Remove notification after 3 seconds
    setTimeout(() => {
        document.body.removeChild(notification);
    }, 3000);
    
    // Log activity
    logActivity('System', 'Settings reset to defaults');
}

// ======== Data Management ========

/**
 * Fetch latest sensor data from the API
 * @param {boolean} forceRefresh - Force refresh even if we have recent data
 */
async function fetchLatestData(forceRefresh = false) {
    try {
        // Show loading indicator
        elements.connectionStatus.innerHTML = '<div class="loading-spinner mr-2 inline-block"></div> Updating...';
        
        // Build request with caching headers
        const headers = {};
        if (state.etag && !forceRefresh) {
            headers['If-None-Match'] = state.etag;
        }
        
        // Use fetch with timeout for better performance on low-end devices
        const controller = new AbortController();
        const timeoutId = setTimeout(() => controller.abort(), 5000);
        
        const response = await fetch('/api/latest', {
            headers,
            signal: controller.signal
        });
        
        clearTimeout(timeoutId);
        
        // Update connection status
        elements.connectionStatus.innerHTML = '<span class="pulse mr-1.5"></span>Live Data';
        
        // If data hasn't changed, don't update
        if (response.status === 304) {
            console.log('Data not modified, using cached version');
            return;
        }
        
        // If response is not OK, throw error
        if (!response.ok) {
            throw new Error(`API error: ${response.status}`);
        }
        
        // Get ETag for future requests
        const newEtag = response.headers.get('ETag');
        if (newEtag) {
            state.etag = newEtag;
        }
        
        // Parse response
        const data = await response.json();
        
        // Save data to state
        state.data = data;
        
        // If time series data is included, save it
        if (data.timeSeriesData) {
            state.timeSeriesData = data.timeSeriesData;
        }
        
        // Update UI with new data
        updateDashboard(data);
        
        // Save last update time
        state.lastUpdate = new Date();
        
        // Update charts if visible
        if (state.navState === 'charts-section') {
            updateCharts();
        }
        
        // Log activity for significant changes
        logDataActivity(data);
        
        return data;
    } catch (error) {
        // Handle fetch errors
        console.error('Error fetching data:', error);
        
        if (error.name === 'AbortError') {
            console.log('Request timed out');
            elements.connectionStatus.innerHTML = '<span class="pulse mr-1.5 bg-yellow-400"></span>Slow Connection';
        } else {
            elements.connectionStatus.innerHTML = '<span class="pulse mr-1.5 bg-red-500"></span>Connection Error';
        }
        
        // If we're offline, show notification
        if (!navigator.onLine) {
            handleOfflineStatus();
        }
        
        return null;
    }
}

/**
 * Fetch system status information
 */
async function fetchSystemStatus() {
    try {
        const response = await fetch('/api/system/info');
        
        if (!response.ok) {
            throw new Error(`API error: ${response.status}`);
        }
        
        const data = await response.json();
        
        // Update system status UI
        updateSystemStatus(data);
        
        return data;
    } catch (error) {
        console.error('Error fetching system status:', error);
        
        // Show error message in system status section
        if (elements.cpuValue) elements.cpuValue.textContent = 'Error';
        if (elements.memoryValue) elements.memoryValue.textContent = 'Error';
        if (elements.diskValue) elements.diskValue.textContent = 'Error';
        if (elements.networkValue) elements.networkValue.textContent = 'Error';
        
        return null;
    }
}

/**
 * Update dashboard with latest data
 * @param {Object} data - Sensor data
 */
function updateDashboard(data) {
    if (!data) return;
    
    // Update timestamp
    updateTimestamp();
    
    // Update device ID if available
    if (data.deviceID && elements.deviceId) {
        elements.deviceId.textContent = `Device: ${data.deviceID}`;
    }
    
    // Update sensor values
    updateSensorValues(data);
    
    // Update water tank visualization
    updateWaterTankFromData(data);
    
    // Update health assessment
    updateHealthAssessment(data);
}

/**
 * Update timestamp display
 */
function updateTimestamp() {
    if (elements.lastUpdate) {
        const now = new Date();
        const formattedTime = now.toLocaleTimeString();
        elements.lastUpdate.textContent = `Updated: ${formattedTime}`;
    }
}

/**
 * Update sensor value displays
 * @param {Object} data - Sensor data
 */
function updateSensorValues(data) {
    // Process temperature
    if (data.temperature) {
        const temp = data.temperature.value;
        let displayTemp = temp;
        let unit = '°C';
        
        // Convert to Fahrenheit if needed
        if (config.temperatureUnit === 'fahrenheit') {
            displayTemp = (temp * 9/5) + 32;
            unit = '°F';
        }
        
        // Update temperature display (rounded to 1 decimal place)
        const tempRounded = Math.round(displayTemp * 10) / 10;
        if (elements.tempSummary) elements.tempSummary.textContent = `${tempRounded}${unit}`;
        if (elements.temperatureValue) elements.temperatureValue.textContent = tempRounded;
        
        // Update temperature gauge (assuming range 15-30°C)
        const tempPercent = Math.min(100, Math.max(0, ((temp - 15) / 15) * 100));
        if (elements.temperatureGauge) elements.temperatureGauge.style.width = `${tempPercent}%`;
        
        // Update temperature status
        updateStatusBadge(elements.tempStatus, temp, 18, 25, 15, 30);
    }
    
    // Process pH
    if (data.pH) {
        const ph = data.pH.value;
        
        // Update pH display (rounded to 2 decimal places)
        const phRounded = Math.round(ph * 100) / 100;
        if (elements.phSummary) elements.phSummary.textContent = phRounded;
        if (elements.phValue) elements.phValue.textContent = phRounded;
        
        // Update pH gauge (assuming range 4-9)
        const phPercent = Math.min(100, Math.max(0, ((ph - 4) / 5) * 100));
        if (elements.phGauge) elements.phGauge.style.width = `${phPercent}%`;
        
        // Update pH status based on ideal range for plants (usually 5.5-6.5)
        updateStatusBadge(elements.phStatus, ph, 5.5, 6.5, 5.0, 7.0);
    }
    
    // Process ORP
    if (data.ORP) {
        const orp = data.ORP.value;
        
        // Update ORP display
        if (elements.orpValue) elements.orpValue.textContent = Math.round(orp);
        
        // Update ORP gauge (assuming range 150-600)
        const orpPercent = Math.min(100, Math.max(0, ((orp - 150) / 450) * 100));
        if (elements.orpGauge) elements.orpGauge.style.width = `${orpPercent}%`;
        
        // Update ORP status 
        const orpStatusElement = document.querySelector('#orp-card .status-badge');
        updateStatusBadge(orpStatusElement, orp, 300, 400, 200, 500);
    }
    
    // Process TDS
    if (data.TDS) {
        const tds = data.TDS.value;
        
        // Update TDS display
        if (elements.tdsSummary) elements.tdsSummary.textContent = `${Math.round(tds)}ppm`;
        if (elements.tdsValue) elements.tdsValue.textContent = Math.round(tds);
        
        // Update TDS gauge (assuming range 0-500)
        const tdsPercent = Math.min(100, Math.max(0, (tds / 500) * 100));
        if (elements.tdsGauge) elements.tdsGauge.style.width = `${tdsPercent}%`;
        
        // Update TDS status
        updateStatusBadge(elements.tdsStatus, tds, 100, 300, 50, 400);
    }
    
    // Process EC
    if (data.EC) {
        const ec = data.EC.value;
        
        // Update EC display
        if (elements.ecSummary) elements.ecSummary.textContent = `${Math.round(ec)}μS/cm`;
        if (elements.ecValue) elements.ecValue.textContent = Math.round(ec);
        
        // Update EC gauge (assuming range 0-40)
        const ecPercent = Math.min(100, Math.max(0, (ec / 40) * 100));
        if (elements.ecGauge) elements.ecGauge.style.width = `${ecPercent}%`;
        
        // Update EC status
        updateStatusBadge(elements.ecStatus, ec, 10, 25, 5, 35);
    }
    
    // Process water level (distance)
    if (data.distance) {
        const distance = data.distance.value;
        
        // Update distance display
        if (elements.waterSummary) elements.waterSummary.textContent = `${Math.round(distance * 10) / 10}cm`;
        if (elements.distanceValue) elements.distanceValue.textContent = Math.round(distance * 10) / 10;
        
        // Update distance gauge
        const distRange = config.tankMaxDistance - config.tankMinDistance;
        const distPercent = 100 - Math.min(100, Math.max(0, ((distance - config.tankMinDistance) / distRange) * 100));
        if (elements.distanceGauge) elements.distanceGauge.style.width = `${distPercent}%`;
        
        // Update distance status
        const distanceStatusElement = document.querySelector('#distance-card .status-badge');
        const maxGoodRange = config.tankMinDistance + (distRange * 0.3);
        const maxOkRange = config.tankMinDistance + (distRange * 0.7);
        
        // For water level, lower distance is better (fuller tank)
        updateStatusBadge(distanceStatusElement, distance, config.tankMinDistance, maxGoodRange, config.tankMinDistance, maxOkRange, true);
    }
}

/**
 * Update status badge based on value ranges
 * @param {Element} element - Status badge element
 * @param {number} value - Current value
 * @param {number} goodLow - Lower bound of "good" range
 * @param {number} goodHigh - Upper bound of "good" range
 * @param {number} okLow - Lower bound of "ok" range
 * @param {number} okHigh - Upper bound of "ok" range
 * @param {boolean} reverse - Reverse the logic (for water level where lower is better)
 */
function updateStatusBadge(element, value, goodLow, goodHigh, okLow, okHigh, reverse = false) {
    if (!element) return;
    
    // Remove existing status classes
    element.classList.remove('status-ok', 'status-warning', 'status-alert', 'bg-green-100', 'text-green-800', 'bg-yellow-100', 'text-yellow-800', 'bg-red-100', 'text-red-800');
    
    let status = '';
    let statusClass = '';
    
    if (reverse) {
        // Reverse logic (for water level where lower distance is better)
        if (value <= goodHigh) {
            status = 'Good';
            statusClass = 'status-ok';
            element.classList.add('bg-green-100', 'text-green-800');
        } else if (value <= okHigh) {
            status = 'OK';
            statusClass = 'status-warning';
            element.classList.add('bg-yellow-100', 'text-yellow-800');
        } else {
            status = 'Low';
            statusClass = 'status-alert';
            element.classList.add('bg-red-100', 'text-red-800');
        }
    } else {
        // Normal logic
        if (value >= goodLow && value <= goodHigh) {
            status = 'Good';
            statusClass = 'status-ok';
            element.classList.add('bg-green-100', 'text-green-800');
        } else if (value >= okLow && value <= okHigh) {
            status = value < goodLow ? 'Low' : 'High';
            statusClass = 'status-warning';
            element.classList.add('bg-yellow-100', 'text-yellow-800');
        } else {
            status = value < okLow ? 'Too Low' : 'Too High';
            statusClass = 'status-alert';
            element.classList.add('bg-red-100', 'text-red-800');
        }
    }
    
    element.textContent = status;
    element.classList.add(statusClass);
}

/**
 * Update the water tank visualization
 * @param {number} fillPercentage - Fill percentage (0-100)
 */
function updateWaterTank(fillPercentage) {
    if (!elements.waterFill || !elements.tankLevelPercentage) return;
    
    // Ensure the percentage is within bounds
    fillPercentage = Math.min(100, Math.max(0, fillPercentage));
    
    // Calculate fill height (SVG is 100 x 160 with tank from y=10 to y=150)
    const maxFillHeight = 140; // Tank height in SVG
    const fillHeight = (fillPercentage / 100) * maxFillHeight;
    const yPosition = 150 - fillHeight;
    
    // Apply properties directly for better performance than animation
    elements.waterFill.setAttribute('height', fillHeight);
    elements.waterFill.setAttribute('y', yPosition);
    
    // Update percentage text
    elements.tankLevelPercentage.textContent = `${Math.round(fillPercentage)}%`;
}

/**
 * Update the water tank visualization from sensor data
 * @param {Object} data - Sensor data
 */
function updateWaterTankFromData(data) {
    if (!data || !data.distance || !elements.waterFill) return;
    
    const distance = data.distance.value;
    
    // Calculate fill percentage based on min and max distance
    const distRange = config.tankMaxDistance - config.tankMinDistance;
    let fillPercentage = 100 - Math.min(100, Math.max(0, ((distance - config.tankMinDistance) / distRange) * 100));
    
    // Update the tank visualization
    updateWaterTank(fillPercentage);
}

/**
 * Update health assessment based on sensor data
 * @param {Object} data - Sensor data
 */
function updateHealthAssessment(data) {
    if (!data) return;
    
    // Calculate overall health percentage
    let overallHealth = 100;
    let waterQuality = 100;
    let issues = [];
    let recommendations = [];
    
    // Check temperature
    if (data.temperature) {
        const temp = data.temperature.value;
        if (temp < 18 || temp > 25) {
            overallHealth -= 10;
            issues.push('Temperature');
            
            if (temp < 18) {
                recommendations.push('Temperature is below optimal range. Consider raising the ambient temperature.');
            } else {
                recommendations.push('Temperature is above optimal range. Consider cooling the environment.');
            }
        }
    }
    
    // Check pH
    if (data.pH) {
        const ph = data.pH.value;
        if (ph < 5.5 || ph > 6.5) {
            overallHealth -= 15;
            waterQuality -= 20;
            issues.push('pH');
            
            if (ph < 5.5) {
                recommendations.push('pH is too low. Add pH UP solution to raise the pH level.');
            } else {
                recommendations.push('pH is too high. Add pH DOWN solution to lower the pH level.');
            }
        }
    }
    
    // Check TDS
    if (data.TDS) {
        const tds = data.TDS.value;
        if (tds < 100 || tds > 300) {
            overallHealth -= 15;
            waterQuality -= 30;
            issues.push('TDS');
            
            if (tds < 100) {
                recommendations.push('Nutrient concentration (TDS) is low. Add more nutrient solution.');
            } else {
                recommendations.push('Nutrient concentration (TDS) is high. Dilute the nutrient solution with water.');
            }
        }
    }
    
    // Check EC
    if (data.EC) {
        const ec = data.EC.value;
        if (ec < 10 || ec > 25) {
            waterQuality -= 15;
            issues.push('EC');
            
            if (ec < 10) {
                recommendations.push('Water conductivity (EC) is low. Check and adjust nutrient levels.');
            } else {
                recommendations.push('Water conductivity (EC) is high. Dilute the nutrient solution.');
            }
        }
    }
    
    // Check water level
    if (data.distance) {
        const distance = data.distance.value;
        const distRange = config.tankMaxDistance - config.tankMinDistance;
        const maxOkRange = config.tankMinDistance + (distRange * 0.7);
        
        if (distance > maxOkRange) {
            overallHealth -= 10;
            issues.push('Water Level');
            recommendations.push('Water level is low. Refill the water tank.');
        }
    }
    
    // Ensure values are within bounds
    overallHealth = Math.max(0, Math.min(100, overallHealth));
    waterQuality = Math.max(0, Math.min(100, waterQuality));
    
    // Update health indicators
    if (elements.overallHealthValue) elements.overallHealthValue.textContent = `${Math.round(overallHealth)}%`;
    if (elements.overallHealthBar) elements.overallHealthBar.style.width = `${overallHealth}%`;
    
    if (elements.waterQualityValue) elements.waterQualityValue.textContent = `${Math.round(waterQuality)}%`;
    if (elements.waterQualityBar) elements.waterQualityBar.style.width = `${waterQuality}%`;
    
    // Update health status text and indicator
    if (elements.healthStatus && elements.healthIndicator) {
        let statusText = 'Good Condition';
        let statusClass = 'bg-green-100 text-green-500';
        let statusIcon = '<svg xmlns="http://www.w3.org/2000/svg" class="h-8 w-8" fill="none" viewBox="0 0 24 24" stroke="currentColor"><path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M5 13l4 4L19 7" /></svg>';
        
        if (overallHealth < 60) {
            statusText = 'Poor Condition';
            statusClass = 'bg-red-100 text-red-500';
            statusIcon = '<svg xmlns="http://www.w3.org/2000/svg" class="h-8 w-8" fill="none" viewBox="0 0 24 24" stroke="currentColor"><path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M12 9v2m0 4h.01m-6.938 4h13.856c1.54 0 2.502-1.667 1.732-3L13.732 4c-.77-1.333-2.694-1.333-3.464 0L3.34 16c-.77 1.333.192 3 1.732 3z" /></svg>';
        } else if (overallHealth < 80) {
            statusText = 'Fair Condition';
            statusClass = 'bg-yellow-100 text-yellow-500';
            statusIcon = '<svg xmlns="http://www.w3.org/2000/svg" class="h-8 w-8" fill="none" viewBox="0 0 24 24" stroke="currentColor"><path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M12 9v2m0 4h.01m-6.938 4h13.856c1.54 0 2.502-1.667 1.732-3L13.732 4c-.77-1.333-2.694-1.333-3.464 0L3.34 16c-.77 1.333.192 3 1.732 3z" /></svg>';
        }
        
        elements.healthStatus.textContent = statusText;
        
        // Update health indicator
        elements.healthIndicator.className = `w-16 h-16 rounded-full ${statusClass} flex items-center justify-center mr-4 flex-shrink-0`;
        elements.healthIndicator.innerHTML = statusIcon;
    }
    
    // Update recommendation box
    if (elements.recommendationText) {
        if (recommendations.length > 0) {
            // Pick the most important recommendation (first one)
            elements.recommendationText.textContent = recommendations[0];
        } else {
            elements.recommendationText.textContent = 'All parameters are within optimal ranges. Continue current care regimen.';
        }
    }
}

/**
 * Add an entry to the activity log
 * @param {string} source - Activity source
 * @param {string} message - Activity message
 */
function logActivity(source, message) {
    // Create timestamp
    const now = new Date();
    const time = now.toLocaleTimeString();
    
    // Create activity entry object
    const activity = {
        source,
        message,
        time,
        timestamp: now.getTime()
    };
    
    // Add to state
    state.activityLog.unshift(activity);
    
    // Keep only the last 10 entries
    if (state.activityLog.length > 10) {
        state.activityLog.pop();
    }
    
    // Update activity log UI
    updateActivityLog();
}

/**
 * Log activities based on data changes
 * @param {Object} data - Sensor data
 */
function logDataActivity(data) {
    if (!data || !state.data) return;
    
    // Check for significant changes in key metrics
    const metrics = ['temperature', 'pH', 'TDS', 'EC', 'distance'];
    
    metrics.forEach(metric => {
        if (data[metric] && state.data[metric]) {
            const newValue = data[metric].value;
            const oldValue = state.data[metric].value;
            
            // Check for significant change (more than 5% or 0.3 units for pH)
            let significantChange = false;
            
            if (metric === 'pH') {
                significantChange = Math.abs(newValue - oldValue) >= 0.3;
            } else {
                // For other metrics, check for 5% change
                significantChange = Math.abs((newValue - oldValue) / oldValue) >= 0.05;
            }
            
            if (significantChange) {
                let unitLabel = '';
                switch (metric) {
                    case 'temperature': unitLabel = '°C'; break;
                    case 'pH': unitLabel = ''; break;
                    case 'TDS': unitLabel = 'ppm'; break;
                    case 'EC': unitLabel = 'μS/cm'; break;
                    case 'distance': unitLabel = 'cm'; break;
                }
                
                // Format values to 1 decimal place
                const formattedOld = Math.round(oldValue * 10) / 10;
                const formattedNew = Math.round(newValue * 10) / 10;
                
                // Create message
                const message = `${metric.charAt(0).toUpperCase() + metric.slice(1)} changed from ${formattedOld}${unitLabel} to ${formattedNew}${unitLabel}`;
                
                // Log activity
                logActivity('Sensor', message);
            }
        }
    });
}

/**
 * Update activity log UI
 */
function updateActivityLog() {
    if (!elements.activityLog) return;
    
    // Clear placeholder if exists
    const placeholder = elements.activityLog.querySelector('.activity-placeholder');
    if (placeholder) {
        elements.activityLog.innerHTML = '';
    }
    
    // Check if we have activities
    if (state.activityLog.length === 0) {
        elements.activityLog.innerHTML = `
            <div class="flex items-start">
                <div class="flex-shrink-0 h-8 w-8 rounded-full bg-gray-100 flex items-center justify-center text-gray-400">
                    <svg xmlns="http://www.w3.org/2000/svg" class="h-5 w-5" viewBox="0 0 20 20" fill="currentColor">
                        <path fill-rule="evenodd" d="M18 10a8 8 0 11-16 0 8 8 0 0116 0zm-7-4a1 1 0 11-2 0 1 1 0 012 0zM9 9a1 1 0 000 2v3a1 1 0 001 1h1a1 1 0 100-2v-3a1 1 0 00-1-1H9z" clip-rule="evenodd" />
                    </svg>
                </div>
                <div class="ml-3 flex-1">
                    <p class="text-sm font-medium text-gray-400">No recent activity</p>
                    <p class="text-sm text-gray-300">Activity will appear here</p>
                </div>
            </div>
        `;
        return;
    }
    
    // Generate HTML for each activity
    let html = '';
    
    state.activityLog.forEach(activity => {
        // Determine icon based on source
        let iconBg = 'bg-green-100';
        let iconColor = 'text-green-500';
        let iconSvg = '<svg xmlns="http://www.w3.org/2000/svg" class="h-5 w-5" viewBox="0 0 20 20" fill="currentColor"><path fill-rule="evenodd" d="M18 10a8 8 0 11-16 0 8 8 0 0116 0zm-7-4a1 1 0 11-2 0 1 1 0 012 0zM9 9a1 1 0 000 2v3a1 1 0 001 1h1a1 1 0 100-2v-3a1 1 0 00-1-1H9z" clip-rule="evenodd" /></svg>';
        
        if (activity.source === 'Sensor') {
            iconBg = 'bg-blue-100';
            iconColor = 'text-blue-500';
            iconSvg = '<svg xmlns="http://www.w3.org/2000/svg" class="h-5 w-5" viewBox="0 0 20 20" fill="currentColor"><path d="M13 7H7v6h6V7z" /><path fill-rule="evenodd" d="M7 2a1 1 0 012 0v1h2V2a1 1 0 112 0v1h2a2 2 0 012 2v2h1a1 1 0 110 2h-1v2h1a1 1 0 110 2h-1v2a2 2 0 01-2 2h-2v1a1 1 0 11-2 0v-1H9v1a1 1 0 11-2 0v-1H5a2 2 0 01-2-2v-2H2a1 1 0 110-2h1V9H2a1 1 0 010-2h1V5a2 2 0 012-2h2V2zM5 5h10v10H5V5z" clip-rule="evenodd" /></svg>';
        } else if (activity.source === 'Error') {
            iconBg = 'bg-red-100';
            iconColor = 'text-red-500';
            iconSvg = '<svg xmlns="http://www.w3.org/2000/svg" class="h-5 w-5" viewBox="0 0 20 20" fill="currentColor"><path fill-rule="evenodd" d="M18 10a8 8 0 11-16 0 8 8 0 0116 0zm-7 4a1 1 0 11-2 0 1 1 0 012 0zm-1-9a1 1 0 00-1 1v4a1 1 0 102 0V6a1 1 0 00-1-1z" clip-rule="evenodd" /></svg>';
        }
        
        html += `
            <div class="flex items-start">
                <div class="flex-shrink-0 h-8 w-8 rounded-full ${iconBg} flex items-center justify-center ${iconColor}">
                    ${iconSvg}
                </div>
                <div class="ml-3 flex-1">
                    <p class="text-sm font-medium text-gray-900">${activity.message}</p>
                    <p class="text-sm text-gray-500">${activity.source} • <time datetime="${new Date(activity.timestamp).toISOString()}">${activity.time}</time></p>
                </div>
            </div>
        `;
    });
    
    // Update activity log
    elements.activityLog.innerHTML = html;
}

/**
 * Update system status UI
 * @param {Object} data - System status data
 */
function updateSystemStatus(data) {
    if (!data) return;
    
    // Update CPU usage
    if (data.cpu) {
        if (elements.cpuGauge) elements.cpuGauge.style.width = `${data.cpu.percent}%`;
        if (elements.cpuValue) elements.cpuValue.textContent = `${data.cpu.percent}%`;
        if (elements.cpuCores) elements.cpuCores.textContent = `${data.cpu.cores} cores`;
    }
    
    // Update memory usage
    if (data.memory) {
        if (elements.memoryGauge) elements.memoryGauge.style.width = `${data.memory.percent}%`;
        if (elements.memoryValue) elements.memoryValue.textContent = `${data.memory.percent}%`;
    }
    
    // Update disk usage
    if (data.disk) {
        if (elements.diskGauge) elements.diskGauge.style.width = `${data.disk.percent}%`;
        if (elements.diskValue) elements.diskValue.textContent = `${data.disk.percent}%`;
    }
    
    // Update network usage
    if (data.network) {
        if (elements.networkGauge) elements.networkGauge.style.width = `${data.network.percent}%`;
        if (elements.networkValue) elements.networkValue.textContent = `${data.network.percent}%`;
    }
    
    // Update other system info if available
    if (data.uptime) {
        const uptimeElement = document.getElementById('uptime');
        if (uptimeElement) uptimeElement.textContent = data.uptime;
    }
    
    if (data.lastBoot) {
        const lastBootElement = document.getElementById('last-boot');
        if (lastBootElement) lastBootElement.textContent = data.lastBoot;
    }
    
    if (data.os) {
        const osInfoElement = document.getElementById('os-info');
        if (osInfoElement) osInfoElement.textContent = data.os;
    }
}
}
}
}
}
/**
 * Apply theme colors based on user preference
 * @param {string} theme - Theme name
 */