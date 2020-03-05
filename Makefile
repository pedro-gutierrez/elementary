define start
	@ELEMENTARY_HOME=${PWD}/examples/$(1) ELEMENTARY_ASSETS=${PWD}/examples/$(1)/assets iex -S mix
endef

fullpass:
	$(call  start,fullpass)

hours:
	$(call  start,hours)
