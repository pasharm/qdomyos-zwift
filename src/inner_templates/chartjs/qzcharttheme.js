// Modern look (fork only): the Chart.js charts of the web pages follow the app theme.
// A page creates its charts with qzChartTheme.create(ctx, config) instead of new Chart().
// Without html.modern (the classic look, or a page opened without the theme fragment) the
// config is left as it is. In the dark theme the neutral colours - black and grey text, grid
// lines drawn for white, the black target line, the white canvas fill - take the theme
// colours; the colours that carry meaning (zones, metrics) stay. The chart images saved for
// the workout mail (qzChartTheme.image) are always drawn in the original light look.
(function () {
    // Colours drawn for a white background, replaced in the dark theme
    var NEUTRAL = /^(black|#000|#000000|#666|#666666|rgb\(0,\s*0,\s*0\)|rgba\(0,\s*0,\s*0,[^)]*\))$/i;
    var charts = [];

    function palette() {
        var root = document.documentElement;
        if (!root.classList.contains('modern')) {
            return null;
        }
        var css = getComputedStyle(root);
        function v(name, fallback) {
            var s = css.getPropertyValue(name).trim();
            return s || fallback;
        }
        return {
            dark: !root.classList.contains('light'),
            bg: v('--qz-surface', '#1b1f27'),
            text: v('--qz-text', '#e6e8ee'),
            muted: v('--qz-muted', '#9aa1ad'),
            grid: 'rgba(255, 255, 255, 0.07)',
            axis: 'rgba(255, 255, 255, 0.16)'
        };
    }

    function isNeutral(c) {
        return c === undefined || (typeof c === 'string' && NEUTRAL.test(c.trim()));
    }

    // Paths, not object references: Chart.js rebuilds options.scales on every update
    function get(root, path) {
        var o = root;
        for (var i = 0; i < path.length; i++) {
            if (o === undefined || o === null) {
                return undefined;
            }
            o = o[path[i]];
        }
        return o;
    }

    function set(root, path, value) {
        var o = root;
        for (var i = 0; i < path.length - 1; i++) {
            if (o[path[i]] === undefined || o[path[i]] === null) {
                if (value === undefined) {
                    return;
                }
                o[path[i]] = {};
            }
            o = o[path[i]];
        }
        if (value === undefined) {
            delete o[path[path.length - 1]];
        } else {
            o[path[path.length - 1]] = value;
        }
    }

    // Each patch: a path, the original value and the value for a theme palette
    function patches(config) {
        var list = [];
        function add(path, themed) {
            var light = get(config, path);
            list.push({ path: path, light: light, themed: function (pal) { return themed(pal, light); } });
        }
        function neutral(pal, light, darkValue) {
            return pal.dark && isNeutral(light) ? darkValue : light;
        }

        var scales = (config.options && config.options.scales) || {};
        var ids = Object.keys(scales);
        ['x', 'y'].forEach(function (id) {
            if (ids.indexOf(id) < 0) {
                ids.push(id);
            }
        });
        ids.forEach(function (id) {
            var s = ['options', 'scales', id];
            add(s.concat(['ticks', 'color']), function (pal, light) {
                return neutral(pal, light, light === 'black' ? pal.text : pal.muted);
            });
            add(s.concat(['title', 'color']), function (pal, light) { return neutral(pal, light, pal.muted); });
            add(s.concat(['grid', 'color']), function (pal, light) { return neutral(pal, light, pal.grid); });
            add(s.concat(['grid', 'borderColor']), function (pal, light) { return neutral(pal, light, pal.axis); });
        });

        add(['options', 'plugins', 'title', 'color'], function (pal, light) { return neutral(pal, light, pal.text); });
        add(['options', 'plugins', 'title', 'font', 'weight'], function () { return '600'; });
        add(['options', 'plugins', 'legend', 'labels', 'color'], function (pal, light) { return neutral(pal, light, pal.muted); });

        // The zone bands: lighter on a dark card, so the line over them stands out, and with
        // the borders of the grid instead of the plugin's grey
        var annotations = get(config, ['options', 'plugins', 'annotation', 'annotations']) || {};
        Object.keys(annotations).forEach(function (key) {
            var a = ['options', 'plugins', 'annotation', 'annotations', key];
            add(a.concat(['backgroundColor']), function (pal, light) {
                return pal.dark && typeof light === 'string' ? light.replace(/,\s*0\.55\)$/, ', 0.3)') : light;
            });
            add(a.concat(['borderColor']), function (pal, light) { return neutral(pal, light, pal.axis); });
        });

        // The black target line (Req. Watts, requested resistance and cadence)
        var datasets = get(config, ['data', 'datasets']) || [];
        datasets.forEach(function (ds, i) {
            ['borderColor', 'backgroundColor'].forEach(function (key) {
                if (typeof ds[key] === 'string' && isNeutral(ds[key])) {
                    add(['data', 'datasets', i, key], function (pal, light) { return pal.dark ? pal.text : light; });
                }
            });
        });
        return list;
    }

    function apply(root, list, pal) {
        list.forEach(function (p) {
            set(root, p.path, pal ? p.themed(pal) : p.light);
        });
    }

    function rootOf(chart) {
        return { options: chart.config.options, data: chart.config.data };
    }

    window.qzChartTheme = {
        create: function (ctx, config) {
            var list = patches(config);
            var pal = palette();
            apply(config, list, pal);
            var chart = new Chart(ctx, config);
            chart.$qzPatches = list;
            chart.$qzPalette = pal;
            // Pages that recreate their chart (workout preview) drop the destroyed ones here
            charts = charts.filter(function (c) { return !!c.canvas; });
            charts.push(chart);
            return chart;
        },

        // The fill of the canvas: dochart.js draws it under each chart
        background: function (chart) {
            var pal = chart && chart.$qzPalette;
            return pal && pal.dark ? pal.bg : 'white';
        },

        // After the page theme changes (qzApplyTheme)
        refresh: function () {
            var pal = palette();
            charts = charts.filter(function (chart) { return !!chart.canvas; });
            charts.forEach(function (chart) {
                chart.$qzPalette = pal;
                apply(rootOf(chart), chart.$qzPatches, pal);
                chart.update('none');
            });
        },

        // Runs fn with the chart drawn in the original light look and returns its result; the
        // screen gets the theme back in the same task, so nothing flashes. Redrawing calls the
        // chart's animation.onComplete again: the callers set their "saved" flag first.
        withLight: function (chart, fn) {
            var pal = chart && chart.$qzPalette;
            if (!pal || !chart.$qzPatches) {
                return fn();
            }
            chart.$qzPalette = null;
            apply(rootOf(chart), chart.$qzPatches, null);
            chart.update('none');
            try {
                return fn();
            } finally {
                chart.$qzPalette = pal;
                apply(rootOf(chart), chart.$qzPatches, pal);
                chart.update('none');
            }
        },

        // The chart as a PNG for the workout mail, in the original light look
        image: function (chart) {
            return this.withLight(chart, function () { return chart.toBase64Image(); });
        },

        // html2canvas options: the saved summary badge keeps the classic look. html2canvas
        // copies the canvases synchronously when called, so the call goes inside withLight()
        // for the chart in the badge
        snapshotOptions: function () {
            return {
                onclone: function (doc) {
                    doc.documentElement.classList.remove('modern', 'light');
                }
            };
        }
    };
})();
