#-*-Mode:make;coding:utf-8;tab-width:4;c-basic-offset:4-*-
# ex: set ft=make fenc=utf-8 sts=4 ts=4 sw=4 noet nomod:

instdir = "$(cloudi_prefix)/tests/messaging/ebin"
directinstdir = "$(DESTDIR)$(instdir)"
beamdir = "$(instdir)"
buildbeamdir = ../ebin
APPLICATION = cloudi_service_messaging_sequence.app
beam_DATA = cloudi_service_messaging_sequence1.beam \
            cloudi_service_messaging_sequence2.beam \
            cloudi_service_messaging_sequence3.beam \
            cloudi_service_messaging_sequence4.beam
CLEANFILES = $(beam_DATA) \
             $(buildbeamdir)/$(APPLICATION) \
             $(buildbeamdir)/cloudi_service_messaging_sequence1.beam \
             $(buildbeamdir)/cloudi_service_messaging_sequence2.beam \
             $(buildbeamdir)/cloudi_service_messaging_sequence3.beam \
             $(buildbeamdir)/cloudi_service_messaging_sequence4.beam

all-local: $(beam_DATA) $(srcdir)/$(APPLICATION)
	$(MKDIR_P) $(buildbeamdir) || exit 0
	cp -f $(srcdir)/$(APPLICATION) $(buildbeamdir)
	cp -f $(beam_DATA) $(buildbeamdir)

.erl.beam:
	@ERLC@ -b beam \
           -pz $(top_builddir)/lib/cloudi_core/ebin \
           $(ERLC_OPTS) -o $@ $<

install-exec-hook: $(buildbeamdir)/$(APPLICATION) \
                   $(buildbeamdir)/cloudi_service_messaging_sequence1.beam \
                   $(buildbeamdir)/cloudi_service_messaging_sequence2.beam \
                   $(buildbeamdir)/cloudi_service_messaging_sequence3.beam \
                   $(buildbeamdir)/cloudi_service_messaging_sequence4.beam
	$(MKDIR_P) $(directinstdir)
	$(INSTALL_DATA) $(buildbeamdir)/$(APPLICATION) $(directinstdir)
	$(INSTALL_DATA) $(buildbeamdir)/cloudi_service_messaging_sequence1.beam \
                    $(directinstdir)
	$(INSTALL_DATA) $(buildbeamdir)/cloudi_service_messaging_sequence2.beam \
                    $(directinstdir)
	$(INSTALL_DATA) $(buildbeamdir)/cloudi_service_messaging_sequence3.beam \
                    $(directinstdir)
	$(INSTALL_DATA) $(buildbeamdir)/cloudi_service_messaging_sequence4.beam \
                    $(directinstdir)
