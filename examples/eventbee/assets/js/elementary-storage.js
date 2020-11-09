export default (name, _settings, app) => {
    const ns = "cm:";
    const {encode, update} = app;
    //
    return (_encoders, enc, ctx) => {

        if (!enc) {
            var entries = {};
            for (let [k, v] of Object.entries(window.localStorage)) {
                if (k.startsWith(ns)) {
                    entries[k.substring(ns.length)] = v;
                }
            }
            
            entries.effect = name;
            update(entries);
            return;
        }
        
        var {err, value: spec} = encode(enc, ctx);
        if (err) {
            console.error(`[${name}] error encoding spec`, {err, enc});
            return
        }

        for (let [key, value] of Object.entries(spec)) {
            window.localStorage.setItem(ns + key, value);
        }
    }
}
