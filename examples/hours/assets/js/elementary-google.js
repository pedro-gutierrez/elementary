export default (name, _settings, app) => {
    
    var auth2;

    gapi.load('auth2', function() {
        auth2 = gapi.auth2.init({
            client_id: '968814981880-kootjghn3f2e25bhe5tvpjgidfgdfs2q.apps.googleusercontent.com',
            ux_mode: 'redirect'
          // Scopes to request in addition to 'profile' and 'email'
          //scope: 'additional_scope'
        });

    });


    const { update } = app;

    return (_, action, model) => {
        switch (action.google) {
            case 'signin':
                auth2.grantOfflineAccess().then((authResult) => {
                    update(Object.assign(authResult, {effect: name}));    
                }, (error) => {
                    console.error("error", error);
                });
                break;
            default:
                console.error("Unknown google action", {action, model});

        }
    }
};
