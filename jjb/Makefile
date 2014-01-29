NIGHTLY=kamailio33-nightly.yaml \
        kamailio40-nightly.yaml \
        kamailio41-nightly.yaml  \
        kamailiodev-nightly.yaml
ENABLED=kamailio33.yaml \
        kamailio40.yaml \
        kamailio41.yaml \
        $(NIGHTLY) \
        $(DEV)

DEV=$(addprefix vseva-,$(NIGHTLY))

all: $(ENABLED)

$(ENABLED):
	jenkins-jobs update $@

.PHONY: all $(ENABLED)
