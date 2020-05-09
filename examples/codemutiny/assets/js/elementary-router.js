export default (name, _settings, app) => {

    const {encode, update} = app;
    
    function error(spec, data, reason) {
        console.error(`[${name}]`, {spec, data, reason});
    }

    function route() {
        const uri = decodeURI(window.location.hash.substring(1))

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


        update({ 
            effect: name,
            path: path,
            query: query
        });
    }

    return (_encoders, data, model) => {
        if (!data) return route();
        const {err, value} = encode(data, model);
        if (err) return error(spec, data, err);
        const {action, target} = value;
        switch (action) {
            case 'navigate':
                window.location.hash = '#/' + target;
                return route();
            default:
                console.warn("[elementary-router] not implemented", req);
                return;
        }
    };
}
