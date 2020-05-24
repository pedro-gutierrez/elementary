export default (name, _settings, app) => {

    const {encode, update} = app;

    function error(spec, data, reason) {
        console.error(`[${name}]`, {spec, data, reason});
    }

    function encodeHash(target) {
        var uri = "/" + target.route;
        var queryParts = [];
        if (target.query) {
            for (var q in target.query) {
                if (target.query.hasOwnProperty(q) && target.query[q] &&  target.query[q].length) {
                    queryParts.push(q + "=" + target.query[q]);
                }
            }
        }

        return queryParts.length ? encodeURI(uri + "?" + queryParts.join("&")) : encodeURI(uri);
    }

    function decodeHash(uri) {
        uri = decodeURI(uri);

        var path = "/"
        var query = {}
        if (uri.length) {
            var parts = uri.split("?")
            path = parts[0]
            if (parts.length > 1) {
                parts[1].split('&').map(hk => {
                    let temp = hk.split('=');
                    query[temp[0]] = temp[1]
                });
            }

            if (!path.startsWith("/")) path="/"+path;
        }

        return {path, query};
    }

    return (_encoders, data, model) => {
        if (!data) {
            const {path, query} = decodeHash(window.location.hash.substring(1))
            update({
                effect: name,
                route: path,
                query: query
            });
        } else {
            const {err, value} = encode(data, model);
            if (err) return error(spec, data, err);
            const {action, target} = value;
            switch (action) {
                case 'navigate':
                    window.location.hash = '#' + encodeHash(target);
                    update({
                        effect: name,
                        route: "/" + target.route,
                        query: target.query 

                    });
                    break;
                default:
                    console.warn("[elementary-router] not implemented", value);
            }
        }
    };
}
