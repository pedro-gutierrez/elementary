define start
@ELEMENTARY_HOME=${PWD}/examples/$(1) ELEMENTARY_ASSETS=${PWD}/examples/$(1)/assets MONGO_URL=mongodb://localhost/$1 ELEMENTARY_ADMIN_TOKEN=$1-admin-token PORT=$(2) ELEMENTARY_WEBROOT=http://localhost:$(2) GOOGLE_CLIENT_ID=$(3) GOOGLE_CLIENT_SECRET=$(4) iex -S mix
endef

hours:
	$(call  start,hours,4000,$(GOOGLE_CLIENT_ID),$(GOOGLE_CLIENT_SECRET))

fullpass:
	$(call  start,fullpass,4001)

build:
	@docker build -t pedrogutierrez/elementary:latest .

heroku:
	@docker build -t pedrogutierrez/hours:latest . -f Dockerfile.hours
	@docker tag pedrogutierrez/hours:latest registry.heroku.com/floohours/web
	@docker push registry.heroku.com/floohours/web
	@heroku container:release -a floohours web
