define start
@ELEMENTARY_HOME=${PWD}/examples/$(1) MONGO_URL=mongodb://localhost/$1 ELEMENTARY_ADMIN_TOKEN=$1-admin-token PORT=$(2) ELEMENTARY_WEBROOT=http://localhost:$(2) iex -S mix
endef

codemutiny:
	$(call  start,codemutiny,4002)

hours:
	$(call  start,hours,4000)

fullpass:
	$(call  start,fullpass,4001)

elementary:
	@docker login -u ${DOCKER_USER} -p ${DOCKER_PASS}
	@docker build -t pedrogutierrez/elementary:latest .
	@docker push pedrogutierrez/elementary:latest

heroku: 
	@docker login -u ${HEROKU_LOGIN} -p ${HEROKU_API_KEY} registry.heroku.com
	@echo "FROM pedrogutierrez/elementary:latest" > Dockerfile.$(app)
	@echo "ADD examples/$(app) /etc/$(app)" >> Dockerfile.$(app)
	@echo "ENV ELEMENTARY_HOME=/etc/$(app)" >> Dockerfile.$(app)
	@echo "ENV ELEMENTARY_ASSETS=/etc/$(app)/assets" >> Dockerfile.$(app)
	@docker build -t pedrogutierrez/$(app):latest -f Dockerfile.$(app) .
	@docker tag pedrogutierrez/$(app):latest registry.heroku.com/$(app)/web
	@docker push registry.heroku.com/$(app)/web
	@heroku container:release -a $(app) web
	@rm -rf Dockerfile.$(app)
