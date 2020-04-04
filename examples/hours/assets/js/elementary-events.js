export default (name, settings, app) => {
    const { encode, update } = app;
    return (encoders, enc, model) => {
        const { err, value } = encode(enc, model);
        if (err) {
            console.error("Encode error", err);
        } else {
            var delay = 0;
            if (value.delay && typeof(value.delay) == 'number') {
                delay = value.delay;
            }
            value.effect = name;
            setTimeout(() => { update(value); }, delay);
        }
    }
};
