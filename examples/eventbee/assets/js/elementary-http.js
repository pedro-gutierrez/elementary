export default (name, settings, app) => {
    const { encode, decode, update, tc} = app;

    function baseUrl() {
        if (settings.url) return settings.url;
        var {protocol, host} = window.location;
        return `${protocol}//${host}${settings.path||''}`
    }

    const state = {
        url: baseUrl()
    };

    function error(msg, data){
        console.error(`[${name}] ${msg}`, data);
    }

    function debug(msg, data) {
        if (settings.debug) console.log(`[http][${name}] ${msg}`, data);
    }

    function decodeJson(raw) {
        try {
            return JSON.parse(raw);
        } catch (e) {
            error("error decoding json", { text: raw, reason: e});
            return raw;
        }
    }

    function getHeadersAsObject(xhr){
        let headers = {}
        xhr.getAllResponseHeaders()
            .split('\u000d\u000a')
            .forEach((line) => {
                if (line.length > 0)
                {
                    let delimiter = '\u003a\u0020',
                        header = line.split(delimiter)

                    headers[header.shift().toLowerCase()] = header.join(delimiter)
                }
            })
        return headers
    }

    const JSON_MIME = 'application/json';

    function decodeBody(headers, req) {
        var raw = req.responseText;
        return headers['content-type'] === JSON_MIME ?
            decodeJson(raw) : raw;
    }

    function encodeBody(req, next) {
        let ct = (req.headers || {})["content-type"] || JSON_MIME;
        switch (ct) {
            case JSON_MIME:
                return next(JSON.stringify(req.body), JSON_MIME);
            default:
                var form = new FormData();
                for (var f in req.body) {
                    if (req.body.hasOwnProperty(f)) {
                        form.append(f, req.body[f])
                    }
                }
                return next(form, null);
        }
    }

    function encodeUrl(req) {
        if (req.url) return req.url;
        return (state.url ||'') + (req.path || '')
    }
    
    function encodeQuery(url, req) {
        if (!req.query) return url;

        var qs = [];
        for (var q in req.query) {
            if (req.query.hasOwnProperty(q)) {
                var val = encodeURIComponent(req.query[q]);
                qs.push(`${q}=${val}`)
            }
        }

        return url + "?" + qs.join("&");
    }

    function withReqHeaders(xhr, source) {
        if (source && source.headers) {
            for (var h in source.headers) {
                if (source.headers.hasOwnProperty(h)) {
                    xhr.setRequestHeader(h, source.headers[h]);
                }
            }
        }
    }

    function replyWithError(as, reason) {
        var data = {
            effect: name
        };

        data[as] = reason;
        update(data);
    }

    return (encoders, enc, model) => {
        var {err, value} = encode(enc, model);
                    
        if (err) {
            error("error encoding request", err);
            return;
        }

        var as = value.as;
        var tag = value.tag;

        encodeBody(value, (body, ct) => {
            var method = (value.method || 'get').toUpperCase()
            var url = encodeUrl(value);
            url = encodeQuery(url, value);
            var xhr = new XMLHttpRequest();
            xhr.timeout = 2000;
            xhr.open(method, url);
            withReqHeaders(xhr, settings);
            withReqHeaders(xhr, value);
            xhr.onerror = function (e) {
                replyWithError(as, "error");
            }

            xhr.ontimeout = function () {
                replyWithError(as, "timeout");
            }

            xhr.onload = function () {
                var headers = getHeadersAsObject(xhr);

                var payload = {
                    headers: headers,
                    status: xhr.status,
                    body: decodeBody(headers, xhr)
                }
                
                payload.tag = tag;

                var data = {}
                if (as) {
                    data[as] = payload;
                } else data = payload;
                
                data.effect = name

                if (value.debug) {
                    console.log(name, {
                        request: {
                            url, method, body
                        }, response: data
                    });
                }

                update(data);
            }
            xhr.send(body);
        });
    };
}
