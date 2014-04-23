ENABLED=kamailio.yaml sems.yaml

all: $(ENABLED)

$(ENABLED):
	jenkins-jobs update $@

test:
	mkdir -p config
	$(foreach X,$(ENABLED), \
		jenkins-jobs test -o config $X ; \
	)

clean:
	rm -rf config

.PHONY: all $(ENABLED)
