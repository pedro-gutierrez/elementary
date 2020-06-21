export default (name, settings, app) => {
    const { encode, decode, update, tc } = app;
    const state = {};

    function log(msg, data) {
        if (settings.debug) console.log(msg, data);
    }

    function event(spec, value) {
        var e = { effect: name }
        if (typeof (spec) == 'object') {
            e = Object.assign(spec, e);
            e.value = value;
        } else {
            e[spec] = value || "";
        }

        update(e);
    }

    function error(spec, data, reason) {
        return { err: { spec, data, reason } };
    }

    function evValue(target) {
        var v = target.files || target.value;
        if (v && typeof (v) === 'string') {
            v = v.trimLeft();
            return v.length ? v : null;
        } return v;
    }

    function evProps(ev) {
        return {
            event: {
                key: ev.key
            }
        }
    }

    function debounced(delay, fn) {
        let timerId;
        return function (...args) {
            console.log("delaying event", {args: args});
            if (timerId) {
                clearTimeout(timerId);
            }
            timerId = setTimeout(() => {
                fn(...args);
                timerId = null;
            }, delay);
        }
    }

    //function hash(s) {
    //    for (var i = 0, h = 1; i < s.length; i++)
    //        h = Math.imul(h + s.charCodeAt(i) | 0, 2654435761);
    //    return (h ^ h >>> 17) >>> 0;
    //};

    function resolve(views, spec, ctx) {
        switch (typeof (spec)) {
            case 'object':
                const { err, value } = encode(spec, ctx);
                if (err) return error(spec, ctx, err);
                if (!value) return emptyView();
                if (typeof (value) != 'string') return error(value, ctx, "not_a_string");
                return resolve(views, value, ctx);
            case 'string':
                const resolved = views[spec];
                return resolved ? { view: resolved }
                    : error(spec, ctx, "no_such_view");
            default:
                return error(spec, ctx, "unsupported_view_name_spec");
        }
    }

    function compileList(views, items, ctx) {
        if (!items) return { view: [] };
        var out = [];
        for (var i = 0; i < items.length; i++) {
            var item = items[i];
            const { err, view } = compile(views, item, ctx);
            if (err) return { err };
            out[i] = view;
        }

        return { view: out };
    }

    function compileLoop(views, spec, ctx) {
        var { err, view } = resolve(views, spec.with, ctx);
        if (err) return error(spec, ctx, err);
        var itemView = view;
        var { err, value } = encode(spec.loop, ctx);
        if (err) return error(spec, ctx, err);
        var items = value;
        if (!items || !items.length) return { view: [] };
        var { err, value } = encode(spec.params || "@", ctx);
        if (err) return error(spec, ctx, err);
        var sharedCtx = value;
        var out = [];

        var alias = spec.as;
        for (var i = 0; i < items.length; i++) {
            var item = items[i];
            var itemCtx = Object.assign({}, settings, sharedCtx);
            if (alias) {
                itemCtx[alias] = item;
            } else {
                itemCtx = Object.assign(itemCtx, item);
            }
            var { err, view } = compile(views, itemView, itemCtx);
            if (err) return error(spec, ctx, err);
            out.push(view);
        }
        return { view: out };
    }

    function emptyView() {
        return {view: ['div']};
    }

    function compileViewRef(views, spec, ctx) {
        var { err, value } = encode(spec.view, ctx);
        if (err) return error(spec.view, ctx, "cannot encode referenced view spec");
        if (!value && spec.view.maybe) return emptyView();
        var { err, view } = resolve(views, value, ctx);
        if (err) return error(spec, ctx, err);
        var { err, value } = encode(spec.when || true, ctx);
        if (err) return error(spec, ctx, err);
        if (!value) return emptyView();
        var { err, value } = encode(spec.params || "@", ctx);
        if (err) return error(spec, ctx, err);
        return compile(views, view, Object.assign({}, ctx, value));
    }

    function attrsWithEvHandlers(attrs, ctx) {
        for (var k in attrs) {
            if (attrs.hasOwnProperty(k)) {
                if (k.startsWith("on")) {
                    var spec = attrs[k];
                    var {err, value: eventSpec} = encode(spec, ctx);
                    if (err) {
                        console.error("Error encoding value for event handler", k, spec, err);
                    } else {

                        const handler = (ev) => {
                            if (ev.preventDefault) ev.preventDefault();
                            var eventValue = evValue(ev.target);
                            event(eventSpec, eventValue);
                        }
                        attrs[k] = handler
                    }
                } else if (k === 'value') {
                    attrs[k] = new String(attrs[k]);
                }
            }
        }

        return attrs;
    }

    function compileTag(views, spec, ctx) {
        let { tag, attrs = {}, children = [] } = spec;
        var { err, value } = encode(attrs, ctx);
        if (err) return error(spec, attrs, err);
        var { err, value: shouldDisplay } = encode(spec.when || true, ctx);
        if (err) return error(spec, ctx, err);
        if (!shouldDisplay) return { view: ['div'] };
        var { err, view } = compile(views, children, ctx);
        if (err) return error(spec, children, err);
        var attrs2 = attrsWithEvHandlers(value, ctx);
        return { view: [tag, attrs2].concat(view) };
    }

    function compileText(views, spec, ctx) {
        const { err, value } = encode(spec.text, ctx);
        if (err) return error(spec, ctx, err);
        return { view: value }
    }


    //function displayMap(id, style, zoom, center, markers) {
    //    mapboxgl.accessToken = "pk.eyJ1IjoiY29kZW11dGlueSIsImEiOiJjamk4b3RrZHAwbHVhM3BtNWx1eDg3eXFnIn0.jXq3glh_ARDIsVKUUo9jsw";
    //    var map = new mapboxgl.Map({
    //        container: id,
    //        style: "mapbox://styles/mapbox/" + style + "-v9",
    //        zoom: zoom,
    //        center: [center.lon, center.lat]
    //    });

    //    markers.forEach((marker) => {
    //        var m = new mapboxgl.Marker();
    //        m.setLngLat([marker.lon, marker.lat]);
    //        m.addTo(map);
    //    });
    //}

    //function compileMapbox(views, spec, ctx) {
    //    var {err, value} = encode(spec.map.id, ctx);
    //    if (err) return error(spec, ctx, err);
    //    var id = value;
    //    var {err, value} = encode(spec.map.center, ctx);
    //    if (err) return error(spec, ctx, err);
    //    var center = value;
    //    var {error, value} = encode(spec.map.markers, ctx);
    //    if (err) return error(spec, ctx, err);
    //    var markers = value;
    //
    //    setTimeout(() => {
    //        displayMap(id, spec.map.style, spec.map.zoom, center, markers);
    //    }, 0);

    //    return { view: ['div', {
    //        style: "width: 100%; height: 300px",
    //        id: id
    //    }]};
    //}

    function compileTimestamp(view, spec, ctx) {
        var { err, value } = encode(spec, ctx);
        if (err) return error(spec, ctx, err);
        return { view: value };
    }

    //function compileCode(views, spec, ctx) {
    //    var {err, value} = encode(spec.code.source, ctx);
    //    if (err) return error(spec, ctx, err);
    //    var source = value;
    //    var {err, value} = encode(spec.code.lang, ctx);
    //    if (err) return error(spec, ctx, err);
    //    var lang = 'language-' + value;
    //    if (value === 'json' && typeof(source) === 'object') {
    //        source = JSON.stringify(source, null, 2)
    //    }
    //    var { value } = hljs.highlight(value, source);
    //    var json = window.himalaya.parse(value);
    //    return { view: ['pre', {
    //        class: lang
    //    }, ['code', {
    //        class: lang
    //    }].concat(compileJsons(json))]};
    //}


    function compileCode(views, spec, ctx) {
        var { err, value } = encode(spec.code.source, ctx);
        if (err) return error(spec, ctx, err);
        var source = value;

        var { err, value } = encode(spec.code.lang || 'json', ctx);
        if (err) return error(spec, ctx, err);
        if (value === 'json' && typeof (source) === 'object') {
            source = JSON.stringify(source, null, 2)
        }

        var style = {};
        if (spec.code.style) {
            var {err, value} = encode(spec.code.style, ctx);
            if (err) return error(spec, ctx, err);
            style = value;
        }

        var lang = 'language-' + value;
        style.class = style.class ? (style.class + " " + lang) : lang;
        return {
            view: ['pre', style, [
                'code', {}, source]]
        };
    }


    function compileJsonAttrs(attrs) {
        var out = {};
        attrs.forEach((a) => {
            out[a.key] = a.value;
        });
        return out;
    }

    function compileJson(el) {
        switch (el.type) {
            case 'element':
                return [el.tagName, compileJsonAttrs(el.attributes)]
                    .concat(el.children.map(compileJson));
            case 'text':
                return el
                    .content
                    .replace("&lt;", "<")
                    .replace("&gt;", ">")
                    .replace(/&#(\d+);/g, function (match, dec) {
                        return String.fromCharCode(dec);
                    })

        }
    }

    //function compileJsons(els) {
    //    return els.map(compileJson);
    //}

    //function compileMarkdown(views, spec, ctx) {
    //    var {err, value} = encode(spec.markdown, ctx);
    //    if (err) return error(spec, ctx, err);
    //    var html = marked(value);
    //    var json = window.himalaya.parse(html);
    //    return { view: compileJson(json[0]) };
    //}

    //var chartTypes = {
    //    line: Chartist.Line,
    //    bar: Chartist.Bar
    //}

    //function compileChart(views, spec, ctx) {
    //    var {err, value} = encode(spec.chart.type, ctx);
    //    if (err) return error(spec, ctx, err);
    //    var chartFun = chartTypes[value];
    //    if (!chartFun) return error(spec, ctx, "chart '" + value + "' not supported");
    //    var {err, value} = encode(spec.chart.labels, ctx);
    //    if (err) return error(spec, ctx, err);
    //    var labels = value;
    //    var {err, value} = encode(spec.chart.data, ctx);
    //    if (err) return error(spec, ctx, err);
    //    var data = value;
    //
    //    var low = 0;
    //    if (spec.chart.hasOwnProperty('low')) {
    //        var {err, value} = encode(spec.chart.low, ctx);
    //        if (!err) low = value;
    //    }
    //    var high = 0;
    //    var series = []
    //
    //    var ptMetaFn = (data.length > 1) ? (sLabel, label) => {
    //        return sLabel + '<br>' + label;
    //    } : (_, label) => { return label };

    //    for (var i=0; i<data.length; i++) {
    //        var s = []
    //        for (var j=0; j<data[i].values.length; j++) {
    //            var v =  data[i].values[j];
    //            if (v>high) high = v;
    //            if (v<low) low = v;
    //            s[j] = { meta: ptMetaFn(data[i].title, labels[j]), value: v}
    //        }
    //        series[i] = s;
    //    }

    //    var chartData = {
    //        labels: labels,
    //        series: series
    //    };

    //    var id = 'a' + hash(JSON.stringify(chartData));
    //    var chartOptions = {
    //        axisY: {
    //            offset: 0,
    //            showLabel: false
    //        },
    //        axisX: {
    //            showLabel: false
    //        },
    //        low: low,
    //        high: high,
    //        fullWidth: true,
    //        plugins: [
    //            Chartist.plugins.tooltip({
    //                "class": 'ct-tooltip',
    //                appendToBody: true,
    //                metaIsHTML: true
    //            })
    //        ]
    //    };

    //    setTimeout(() => {
    //        new chartFun('#'+id, chartData, chartOptions);
    //    },0);

    //    return { view: ['div', {
    //        style: "width: 100%; height: 160px; position: relative; overflow: hidden;",
    //        "id": id,
    //        key: id,
    //    }]};
    //}
    //
    //
    //

    function compileErrorView(views, ctx) {
        return compileTag(views, {
            tag: "p",
            attrs: {
                style: {
                    padding: "15px"
                },
                class: "has-text-danger has-background-light"
            },
            children: [
                "There was an error rendering this view",
            ]
        }, ctx);
    }

    function compile(views, spec, ctx) {
        var {view, err} = compileUnsafe(views, spec, ctx);
        if (!err) return {view};
        event("$error", err);
        return compileErrorView(views, ctx);
    }

    function compileUnsafe(views, spec, ctx) {
        if (typeof (spec) == "string") return compileText(views, { text: spec }, ctx);
        if (Array.isArray(spec)) return compileList(views, spec, ctx);
        if (spec.view) return compileViewRef(views, spec, ctx);
        if (spec.tag) return compileTag(views, spec, ctx);
        if (spec.text) return compileText(views, spec, ctx);
        if (spec.loop) return compileLoop(views, spec, ctx);
        //if (spec.map) return compileMapbox(views, spec, ctx);
        if (spec.timestamp) return compileTimestamp(views, spec, ctx);
        if (spec.code) return compileCode(views, spec, ctx);
        if (spec.markdown) return compileMarkdown(views, spec, ctx);
        if (spec.chart) return compileChart(views, spec, ctx);
        return compileText(views, { text: spec }, ctx);
    }

    function render(view, bodyClass) {
        if (bodyClass) document.body.className = bodyClass;
        IncrementalDOM.patch(document.body, jsonml2idom, view);
    }

    function withSettings(ctx) {
        return Object.assign({}, settings, ctx);
    }

    function withContext(spec, ctx) {
        return Object.assign(ctx, { context: spec.context });
    }

    function encodeBodyClass(encoders, model) {
        var enc = encoders["body-class"];
        if (!enc) return {value: null};
        return encode(enc, model);
    }

    return (views, v, model) => {
        var {err, value: bodyClass} = encodeBodyClass(views, model);
        if (err) {
            console.error("Can't compile body class", err);
            return;
        }

        if (v) state.view = v;

        var c = tc(() => {
            return compile(views, state.view, model);
        });
        if (c.res.err) {
            console.error("Can't compile view", c.res.err);
            return;
        }

        var r = tc(() => { render(c.res.view, bodyClass) });
        if (settings.telemetry) {
            console.log("[" + name + "]"
                + "[compile " + c.millis + "ms]"
                + "[render " + r.millis + "ms]");
        }
    }
};
