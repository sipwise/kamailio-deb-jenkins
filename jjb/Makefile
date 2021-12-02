ENABLED=kamailio.yaml kamcli.yaml rtpengine.yaml

all: $(ENABLED)

$(ENABLED):
	./jenkins-jobs-wrapper update $@

test:
	mkdir -p config
	$(foreach X,$(ENABLED), \
		./jenkins-jobs-wrapper test -o config $X ; \
	)

# get rid of test files
clean:
	rm -rf config

# also get rid of pip environment
dist-clean: clean
	rm -rf bin include lib local

.PHONY: all $(ENABLED)
