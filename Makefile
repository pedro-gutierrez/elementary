define start
@ELEMENTARY_HOME=${PWD}/examples/$(1) MONGO_URL=mongodb://localhost/$1 ELEMENTARY_ADMIN_TOKEN=$1-admin-token PORT=$(2) ELEMENTARY_WEBROOT=http://localhost:$(2) iex -S mix
endef

codemutiny:
	$(call  start,codemutiny,4002)

hours:
	$(call  start,hours,4000)

fullpass:
	$(call  start,fullpass,4001)
