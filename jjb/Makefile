ENABLED=kamailio.yaml kamcli.yaml rtpengine.yaml
BUILD=$(addprefix build_, ${ENABLED})

all: $(ENABLED)
.PHONY: all $(BUILD)

$(BUILD): file = $(subst _,-,$(subst build_,,$@))
$(BUILD):
	sed -e '/#:TEMPLATES:#/r templates.yaml.inc' $(file).in > $(file)

$(ENABLED): $(BUILD)
	./jenkins-jobs-wrapper update $@

test: $(BUILD)
	mkdir -p config
	$(foreach X,$(ENABLED), \
		./jenkins-jobs-wrapper test -o config $X ; \
	)

# get rid of test files
clean:
	rm -rf config *.yaml

# also get rid of pip environment
dist-clean: clean
	rm -rf bin include lib local

.PHONY: all $(ENABLED)
