define start
@ELEMENTARY_HOME=${PWD}/examples/$(1) MONGO_URL=mongodb://localhost/$1 ELEMENTARY_ADMIN_TOKEN=$1-admin-token PORT=$(2) ELEMENTARY_WEBROOT=http://localhost:$(2) ELEMENTARY_CLUSTER_SIZE=1 ELEMENTARY_CLUSTER_PREFIX=any iex -S mix
endef

codmutiny:
	$(call  start,codemutiny,4000)

fullpass:
	$(call  start,fullpass,4001)

hours:
	$(call  start,hours,4002)

