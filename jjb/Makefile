ENABLED=kamailio33-nightly.yaml kamailio33.yaml \
        kamailio40-nightly.yaml kamailio40.yaml \
        kamailio41-nightly.yaml kamailio41.yaml \
        kamailiodev-nightly.yaml

all: $(ENABLED)

$(ENABLED):
	jenkins-jobs update $@

.PHONY: all $(ENABLED)
