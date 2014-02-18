ENABLED=kamailio.yaml

all: $(ENABLED)

$(ENABLED):
	jenkins-jobs update $@

test:
	mkdir -p config
	jenkins-jobs test -o config $(ENABLED)

clean:
	rm -rf config

.PHONY: all $(ENABLED)
