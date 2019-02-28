# KVM make targets, for Libreswan
#
# Copyright (C) 2015-2019 Andrew Cagney
#
# This program is free software; you can redistribute it and/or modify it
# under the terms of the GNU General Public License as published by the
# Free Software Foundation; either version 2 of the License, or (at your
# option) any later version.  See <https://www.gnu.org/licenses/gpl2.txt>.
#
# This program is distributed in the hope that it will be useful, but
# WITHOUT ANY WARRANTY; without even the implied warranty of MERCHANTABILITY
# or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU General Public License
# for more details.

# Note: GNU Make doesn't let you combine pattern targets (e.x.,
# kvm-install-%: kvm-reboot-%) with .PHONY.  Consequently, so that
# patterns can be used, any targets with dependencies are not marked
# as .PHONY.  Sigh!

# Note: for pattern targets, the value of % can be found in the make
# variable '$*'.  It is used to extract the DOMAIN from targets like
# kvm-install-DOMAIN.

#
# The guest operating system.
#
# Pull in all its defaults so that they override everything below.

KVM_OS ?= fedora28
include testing/libvirt/$(KVM_OS).mk


#
# where things live and what gets created
#

KVM_SOURCEDIR ?= $(abs_top_srcdir)
KVM_TESTINGDIR ?= $(abs_top_srcdir)/testing
# An educated guess ...
KVM_POOLDIR ?= $(abspath $(abs_top_srcdir)/../pool)
KVM_LOCALDIR ?= $(KVM_POOLDIR)
# While KVM_PREFIX might be empty, KVM_PREFIXES is never empty.
KVM_PREFIX ?=
KVM_PREFIXES ?= $(if $(KVM_PREFIX), $(KVM_PREFIX), '')
KVM_WORKERS ?= 1
#KVM_WORKERS ?= $(shell awk 'BEGIN { c=1 } /cpu cores/ { c=$$4 } END { if (c>1) print c/2; }' /proc/cpuinfo)
KVM_GROUP ?= qemu

# Should these live in the OS.mk file?
KVM_USE_EFENCE ?= true
KVM_USE_NSS_IPSEC_PROFILE ?= true
KVM_ALL_ALGS ?= false
KVM_USE_SECCOMP ?= true
KVM_USE_LABELED_IPSEC ?= true
KVM_MAKEFLAGS ?= USE_EFENCE=$(KVM_USE_EFENCE) ALL_ALGS=$(KVM_ALL_ALGS) USE_SECCOMP=$(KVM_USE_SECCOMP) USE_LABELED_IPSEC=$(KVM_USE_LABELED_IPSEC) USE_NSS_IPSEC_PROFILE=$(KVM_USE_NSS_IPSEC_PROFILE)

KVM_UID ?= $(shell id -u)
KVM_GID ?= $(shell id -g $(KVM_GROUP))

# targets for dumping the above
.PHONY: print-kvm-prefixes
print-kvm-prefixes: ; @echo "$(KVM_PREFIXES)"


#
# Generate local names using prefixes
#

strip-prefix = $(subst '',,$(subst "",,$(1)))
# for-each-kvm-prefix = how?
add-kvm-prefixes = \
	$(foreach prefix, $(KVM_PREFIXES), \
		$(addprefix $(call strip-prefix,$(prefix)),$(1)))
KVM_FIRST_PREFIX = $(call strip-prefix,$(firstword $(KVM_PREFIXES)))


# To avoid the problem where the host has no "default" KVM network
# (there's a rumour that libreswan's main testing machine has this
# problem) define a dedicated swandefault gateway.

KVM_GATEWAY ?= swandefault

# The alternative is qemu:///session and it doesn't require root.
# However, it has never been used, and the python tools all assume
# qemu://system. Finally, it comes with a warning: QEMU usermode
# session is not the virt-manager default.  It is likely that any
# pre-existing QEMU/KVM guests will not be available.  Networking
# options are very limited.

KVM_CONNECTION ?= qemu:///system

VIRSH = sudo virsh --connect $(KVM_CONNECTION)

VIRT_INSTALL ?= sudo virt-install --connect $(KVM_CONNECTION)
VIRT_CPU ?= --cpu host-passthrough
VIRT_DISK_SIZE_GB ?=8
VIRT_RND ?= --rng type=random,device=/dev/random
VIRT_SECURITY ?= --security type=static,model=dac,label='$(KVM_UID):$(KVM_GID)',relabel=yes
VIRT_GATEWAY ?= --network=network:$(KVM_GATEWAY),model=virtio
VIRT_SOURCEDIR ?= --filesystem type=mount,accessmode=squash,source=$(KVM_SOURCEDIR),target=swansource
VIRT_TESTINGDIR ?= --filesystem type=mount,accessmode=squash,source=$(KVM_TESTINGDIR),target=testing
KVM_OS_VARIANT ?= $(KVM_OS)
VIRT_OS_VARIANT ?= --os-variant $(KVM_OS_VARIANT)

#
# Hosts
#

KVM_BASE_HOST = swan$(KVM_OS)base

KVM_BUILD_HOST ?= build

KVM_TEST_HOSTS = $(notdir $(wildcard testing/libvirt/vm/*[a-z]))
KVM_BASIC_HOSTS = nic
KVM_INSTALL_HOSTS = $(filter-out $(KVM_BASIC_HOSTS), $(KVM_TEST_HOSTS))

KVM_LOCAL_HOSTS = $(sort $(KVM_BUILD_HOST) $(KVM_TEST_HOSTS))

KVM_HOSTS = $(KVM_BASE_HOST) $(KVM_LOCAL_HOSTS)

#
# Domains
#

KVM_BASE_DOMAIN = $(addprefix $(KVM_FIRST_PREFIX), $(KVM_BASE_HOST))

KVM_BUILD_DOMAIN = $(addprefix $(KVM_FIRST_PREFIX), $(KVM_BUILD_HOST))

KVM_BASIC_DOMAINS = $(call add-kvm-prefixes, $(KVM_BASIC_HOSTS))
KVM_INSTALL_DOMAINS = $(call add-kvm-prefixes, $(KVM_INSTALL_HOSTS))
KVM_TEST_DOMAINS = $(call add-kvm-prefixes, $(KVM_TEST_HOSTS))

KVM_LOCAL_DOMAINS = $(sort $(KVM_BUILD_DOMAIN) $(KVM_TEST_DOMAINS))

KVM_DOMAINS = $(KVM_BASE_DOMAIN) $(KVM_LOCAL_DOMAINS)

#
# what needs to be copied?
#

KVM_BASE_DOMAIN_CLONES = $(KVM_BASIC_DOMAINS) $(KVM_BUILD_DOMAIN)
KVM_BUILD_DOMAIN_CLONES = $(KVM_INSTALL_DOMAINS)

#
# Other utilities and directories
#

KVMSH ?= $(abs_top_srcdir)/testing/utils/kvmsh.py
KVMRUNNER ?= $(abs_top_srcdir)/testing/utils/kvmrunner.py
KVMRESULTS ?= $(abs_top_srcdir)/testing/utils/kvmresults.py
KVMTEST ?= $(abs_top_srcdir)/testing/utils/kvmtest.py

KVM_OBJDIR = OBJ.kvm

RPM_VERSION = $(shell make showrpmversion)
RPM_PREFIX  = libreswan-$(RPM_VERSION)
RPM_BUILD_CLEAN ?= --rmsource --rmspec --clean

# file to mark keys are up-to-date
KVM_KEYS = testing/x509/keys/up-to-date


#
# For when HOST!=DOMAIN, generate maps from the host rule to the
# domain rule.
#

define kvm-HOST-DOMAIN
  #(info kvm-HOST-DOMAIN prefix=$(1) host=$(2) suffix=$(3))
  .PHONY: $(1)$(2)$(3)
  $(1)$(2)$(3): $(1)$$(addprefix $$(KVM_FIRST_PREFIX),$(2))$(3)
endef


#
# Check that things are correctly configured for creating the KVM
# domains
#

KVM_ENTROPY_FILE ?= /proc/sys/kernel/random/entropy_avail
define check-kvm-entropy
	test ! -r $(KVM_ENTROPY_FILE) || test $(shell cat $(KVM_ENTROPY_FILE)) -gt 100 || $(MAKE) broken-kvm-entropy
endef
.PHONY: check-kvm-entropy broken-kvm-entropy
check-kvm-entropy:
	$(call check-kvm-entropy)
broken-kvm-entropy:
	:
	:  According to $(KVM_ENTROPY_FILE) your computer does not seem to have much entropy.
	:
	:  Check the wiki for hints on how to fix this.
	:
	false


KVM_QEMUDIR ?= /var/lib/libvirt/qemu
define check-kvm-qemu-directory
	test -w $(KVM_QEMUDIR) || $(MAKE) broken-kvm-qemu-directory
endef
.PHONY: check-kvm-qemu-directory broken-kvm-qemu-directory
check-kvm-qemu-directory:
	$(call check-kvm-qemu-directory)
broken-kvm-qemu-directory:
	:
	:  The directory:
	:
	:      $(KVM_QEMUDIR)
	:
	:  is not writeable.  This will break virsh which is
	:  used to manipulate the domains.
	:
	false

#
# Don't create $(KVM_POOLDIR) - let the user do that as it lives
# outside of the current directory tree.
#
# However, do create $(KVM_LOCALDIR) (but not using -p) if it is
# unique and doesn't exist - convention seems to be to point it at
# /tmp/pool which needs to be re-created everytime the host is
# rebooted.
#

define kvm-pooldir-info

  The directory:

      "$(KVM_POOLDIR)"

  specified by KVM_POOLDIR and used to store the base domain disk
  and other files, does not exist.

  Either create the directory or adjust its location by setting
  KVM_POOLDIR in the file:

      Makefile.inc.local

endef

$(KVM_POOLDIR):
	$(info $(kvm-pooldir-info))
	false

ifneq ($(KVM_POOLDIR),$(KVM_LOCALDIR))
$(KVM_LOCALDIR):
	: not -p
	mkdir $(KVM_LOCALDIR)
endif


#
# [re]run the testsuite.
#
# If the testsuite is being run a second time (for instance,
# re-started or re-run) what should happen: run all tests regardless;
# just run tests that have never been started; run tests that haven't
# yet passed?  Since each alternative has merit, let the user decide
# by providing both kvm-test and kvm-retest.

KVM_TESTS ?= testing/pluto

# Given a make command like:
#
#     make kvm-test "KVM_TESTS=$(./testing/utils/kvmresults.py --quick testing/pluto | awk '/output-different/ { print $1 }' )"
#
# then KVM_TESTS ends up containing new lines, strip them out.
STRIPPED_KVM_TESTS = $(strip $(KVM_TESTS))

.PHONY:
web-pages-disabled:
	@echo
	@echo Web-pages disabled.
	@echo
	@echo To enable web pages create the directory: $(LSW_WEBDIR)
	@echo To convert this result into a web page run: make web-page
	@echo

# Run the testsuite.
#
# - depends on kvm-keys and not $(KVM_KEYS) so that the check that the
#   keys are up-to-date is run.
#
# - need local domains shutdown as, otherwise, test domains can refuse
#   to boot because the domain they were cloned from is still running.

define kvm-test
.PHONY: $(1)
$(1): kvm-keys kvm-shutdown-local-domains web-test-prep
	$$(if $$(WEB_ENABLED),,@$(MAKE) -s web-pages-disabled)
	: kvm-test target=$(1) param=$(2)
	$$(call check-kvm-qemu-directory)
	$$(call check-kvm-entropy)
	: KVM_TESTS=$(STRIPPED_KVM_TESTS)
	$$(KVMRUNNER) \
		$$(foreach prefix,$$(KVM_PREFIXES), --prefix $$(prefix)) \
		$$(if $$(KVM_WORKERS), --workers $$(KVM_WORKERS)) \
		$$(if $$(WEB_ENABLED), \
			--publish-hash $$(WEB_HASH) \
			--publish-results $$(WEB_RESULTSDIR) \
			--publish-status $$(WEB_SUMMARYDIR)/status.json) \
		$(2) $$(KVM_TEST_FLAGS) $$(STRIPPED_KVM_TESTS)
	$$(if $$(WEB_ENABLED),,@$(MAKE) -s web-pages-disabled)
endef

# "test" and "check" just runs the entire testsuite.
$(eval $(call kvm-test,kvm-check kvm-test, --test-status "good"))

# "retest" and "recheck" re-run the testsuite updating things that
# didn't pass.
$(eval $(call kvm-test,kvm-retest kvm-recheck, --test-status "good" --skip passed))

# clean up; accept pretty much everything
KVM_TEST_CLEAN_TARGETS = \
	clean-kvm-check kvm-clean-check kvm-check-clean \
	clean-kvm-test kvm-clean-test kvm-test-clean \
	clean-kvm-tests kvm-clean-tests kvm-tests-clean
.PHONY: $(KVM_TEST_CLEAN_TARGETS)
$(KVM_TEST_CLEAN_TARGETS):
	find $(STRIPPED_KVM_TESTS) -name OUTPUT -type d -prune -print0 | xargs -0 -r rm -r

.PHONY: kvm-results
kvm-results:
	$(KVMRESULTS) $(KVM_TEST_FLAGS) $(STRIPPED_KVM_TESTS)
.PHONY: kvm-diffs
kvm-diffs:
	$(KVMRESULTS) $(KVM_TEST_FLAGS) $(STRIPPED_KVM_TESTS) --print diffs

.PHONY: kvm-test-modified kvm-check-modified
KVM_MODIFIED_TESTS = $$(git status testing/pluto | awk '/modified:/ { print $$2 }' | cut -d/ -f1-3 | sort -u)
kvm-test-modified kvm-check-modified:
	$(MAKE) kvm-test KVM_TESTS="$(KVM_MODIFIED_TESTS)"
.PHONY: kvm-diff-modified
kvm-diff-modified:
	./testing/utils/kvmresults.py --print diffs $(KVM_MODIFIED_TESTS)



#
# Build the KVM keys using the KVM.
#
# XXX:
#
# Can't yet force the domain's creation.  This target may have been
# invoked by testing/pluto/Makefile which relies on old domain
# configurations.
#
# Make certain everything is shutdown.  Can't depend on the phony
# target kvm-shutdown-local-domains as that triggers an unconditional
# rebuild.  Instead invoke that rule inline.
#
# "dist_certs.py" can't create a directory called "certs/" on a 9p
# mounted file system (OSError: [Errno 13] Permission denied:
# 'certs/').  In fact, "mkdir xxx/ certs/" half fails (only xxx/ is
# created) so it might even be a problem with the mkdir call!  Get
# around this by first creating the certs in /tmp on the guest, and
# then copying back using a tar file.
#
# "dist_certs.py" always writes its certificates to $(dirname $0).
# Get around this by running a copy of dist_certs.py placed in /tmp.

KVM_KEYS_EXPIRATION_DAY = 7
KVM_KEYS_EXPIRED = find testing/x509/*/ -mtime +$(KVM_KEYS_EXPIRATION_DAY)

.PHONY: kvm-keys
kvm-keys: $(KVM_KEYS)
	$(MAKE) --no-print-directory kvm-keys-up-to-date

# $(KVM_KEYS): | $(KVM_LOCALDIR)/$(KVM_BUILD_DOMAIN).xml
$(KVM_KEYS): $(top_srcdir)/testing/x509/dist_certs.py
$(KVM_KEYS): $(top_srcdir)/testing/x509/strongswan-ec-gen.sh
$(KVM_KEYS): $(top_srcdir)/testing/baseconfigs/all/etc/bind/generate-dnssec.sh
$(KVM_KEYS):
	$(call check-kvm-domain,$(KVM_BUILD_DOMAIN))
	$(call check-kvm-entropy)
	$(call check-kvm-qemu-directory)
	: invoke phony target to shut things down and delete old keys
	$(MAKE) kvm-shutdown-local-domains
	$(MAKE) kvm-keys-clean
	:
	: disable FIPS
	:
	$(KVMSH) $(KVM_BUILD_DOMAIN) rm -f /etc/system-fips
	$(KVMSH) --chdir . $(KVM_BUILD_DOMAIN) ./testing/guestbin/fipsoff
	:
	: create the empty /tmp/x509 directory ready for the keys
	:
	$(KVMSH) $(KVM_BUILD_DOMAIN) rm -rf /tmp/x509
	$(KVMSH) $(KVM_BUILD_DOMAIN) mkdir /tmp/x509
	:
	: per comments, generate everything in /tmp/x509
	:
	$(KVMSH) --chdir . $(KVM_BUILD_DOMAIN) cp -f ./testing/x509/dist_certs.py /tmp/x509
	$(KVMSH) --chdir /tmp/x509 $(KVM_BUILD_DOMAIN) ./dist_certs.py
	$(KVMSH) --chdir . $(KVM_BUILD_DOMAIN) cp -f ./testing/x509/strongswan-ec-gen.sh /tmp/x509
	$(KVMSH) --chdir /tmp/x509 $(KVM_BUILD_DOMAIN) ./strongswan-ec-gen.sh
	:
	: copy the certs from guest to host in a tar ball to avoid 9fs bug
	:
	rm -f testing/x509/kvm-keys.tar
	$(KVMSH) --chdir /tmp/x509 $(KVM_BUILD_DOMAIN) tar cf kvm-keys.tar '*/' nss-pw
	$(KVMSH) --chdir . $(KVM_BUILD_DOMAIN) cp /tmp/x509/kvm-keys.tar testing/x509
	cd testing/x509 && tar xf kvm-keys.tar
	rm -f testing/x509/kvm-keys.tar
	:
	: Also regenerate the DNSSEC keys -- uses host
	:
	$(top_srcdir)/testing/baseconfigs/all/etc/bind/generate-dnssec.sh
	$(KVMSH) --shutdown $(KVM_BUILD_DOMAIN)
	touch $@

KVM_KEYS_CLEAN_TARGETS = clean-kvm-keys kvm-clean-keys kvm-keys-clean
.PHONY: $(KVM_KEYS_CLEAN_TARGETS)
$(KVM_KEYS_CLEAN_TARGETS):
	rm -rf testing/x509/*/
	rm -f testing/x509/nss-pw
	rm -f testing/baseconfigs/all/etc/bind/signed/*.signed
	rm -f testing/baseconfigs/all/etc/bind/keys/*.key
	rm -f testing/baseconfigs/all/etc/bind/keys/*.private
	rm -f testing/baseconfigs/all/etc/bind/dsset/dsset-*
	rm -f testing/x509/kvm-keys.tar

# For moment don't force keys to be re-built.
.PHONY: kvm-keys-up-to-date
kvm-keys-up-to-date:
	@if test $$($(KVM_KEYS_EXPIRED) | wc -l) -gt 0 ; then \
		echo "The following keys are more than $(KVM_KEYS_EXPIRATION_DAY) days old:" ; \
		$(KVM_KEYS_EXPIRED) | sed -e 's/^/  /' ; \
		echo "run 'make kvm-keys-clean kvm-keys' to force an update" ; \
		exit 1 ; \
	fi

#
# Create an RPM for the test domains
#

.PHONY: kvm-rpm
kvm-rpm:
	@echo building rpm for libreswan testing
	mkdir -p ~/rpmbuild/SPECS/
	sed  "s/@IPSECBASEVERSION@/$(RPM_VERSION)/g" packaging/fedora/libreswan-testing.spec.in \
		> ~/rpmbuild/SPECS/libreswan-testing.spec
	mkdir -p ~/rpmbuild/SOURCES
	git archive --format=tar --prefix=$(RPM_PREFIX)/ \
		-o ~/rpmbuild/SOURCES/$(RPM_PREFIX).tar HEAD
	if [ -a Makefile.inc.local ] ; then \
		tar --transform "s|^|$(RPM_PREFIX)/|" -rf ~/rpmbuild/SOURCES/$(RPM_PREFIX).tar Makefile.inc.local ; \
	fi;
	gzip -f ~/rpmbuild/SOURCES/$(RPM_PREFIX).tar
	rpmbuild -ba $(RPM_BUILD_CLEAN) ~/rpmbuild/SPECS/libreswan-testing.spec


#
# Build a pool of networks from scratch
#

# This defines the primitives, the public rules are defined near the
# end.

define create-kvm-network
	:
        : create-kvm-network network=$(1) file=$(2)
	:
	$(VIRSH) net-define '$(2)'
	$(VIRSH) net-autostart '$(1)'
	$(VIRSH) net-start '$(1)'
endef

define destroy-kvm-network
	: destroy-kvm-network network=$(1)
	if $(VIRSH) net-info '$(1)' 2>/dev/null | grep 'Active:.*yes' > /dev/null ; then \
		$(VIRSH) net-destroy '$(1)' ; \
	fi
	if $(VIRSH) net-info '$(1)' >/dev/null 2>&1 ; then \
		$(VIRSH) net-undefine '$(1)' ; \
	fi
endef


#
# The Gateway
#
# Because the gateway is created directly from libvirt/swandefault and
# that file contains hardwired IP addresses, only one is possible.
#
# XXX: Why?  Perhaps it is so that SSHing into the VMs is possible,
# but with lots of VMs what address gets assigned stops being
# predictable.
#

KVM_GATEWAY_FILE = $(KVM_POOLDIR)/$(KVM_GATEWAY).gw

.PHONY: install-kvm-network-$(KVM_GATEWAY)
install-kvm-network-$(KVM_GATEWAY): $(KVM_GATEWAY_FILE)

.PHONY: uninstall-kvm-network-$(KVM_GATEWAY)
uninstall-kvm-network-$(KVM_GATEWAY):
	rm -f $(KVM_GATEWAY_FILE)
	$(call destroy-kvm-network,$(KVM_GATEWAY))

$(KVM_GATEWAY_FILE): | testing/libvirt/net/$(KVM_GATEWAY) $(KVM_POOLDIR)
	$(call destroy-kvm-network,$(KVM_GATEWAY))
	$(call create-kvm-network,$(KVM_GATEWAY),testing/libvirt/net/$(KVM_GATEWAY))
	touch $@

# zap dependent domains

uninstall-kvm-network-$(KVM_GATEWAY): uninstall-kvm-domain-$(KVM_BASE_DOMAIN)
uninstall-kvm-network-$(KVM_GATEWAY): uninstall-kvm-domain-$(KVM_BUILD_DOMAIN)


#
# Test networks.
#
# Since networks survive across reboots and don't use any disk, they
# are stored in $(KVM_POOLDIR) and not $(KVM_LOCALDIR).
#

KVM_TEST_SUBNETS = \
	$(notdir $(wildcard testing/libvirt/net/192_*))

KVM_TEST_NETWORKS = \
	$(call add-kvm-prefixes, $(KVM_TEST_SUBNETS))

KVM_TEST_NETWORK_FILES = \
	$(addsuffix .net, $(addprefix $(KVM_POOLDIR)/, $(KVM_TEST_NETWORKS)))

.PRECIOUS: $(KVM_TEST_NETWORK_FILES)

# <prefix><network>.net; if <prefix> is blank call it swan<network>*
KVM_BRIDGE_NAME = $(strip $(if $(patsubst 192_%,,$*), \
			$*, \
			swan$(subst _,,$(patsubst %192_,,$*))))

$(KVM_POOLDIR)/%.net: | $(KVM_POOLDIR)
	$(call destroy-kvm-network,$*)
	rm -f '$@.tmp'
	echo "<network ipv6='yes'>" 					>> '$@.tmp'
	echo "  <name>$*</name>"					>> '$@.tmp'
	echo "  <bridge name='$(KVM_BRIDGE_NAME)'" >> '$@.tmp'
	echo "          stp='on' delay='0'/>"				>> '$@.tmp'
	$(if $(patsubst 192_%,, $*), \
	echo "  <!--" 							>> '$@.tmp')
	echo "  <ip address='$(subst _,.,$(patsubst %192_, 192_, $*)).253'/>" >> '$@.tmp'
	$(if $(patsubst 192_%,, $*), \
	echo "    -->" 							>> '$@.tmp')
	echo "</network>"						>> '$@.tmp'
	$(call create-kvm-network,$*,$@.tmp)
	mv $@.tmp $@

.PHONY: kvm-install-test-networks
kvm-install-test-networks: $(KVM_TEST_NETWORK_FILES)
.PHONY: kvm-uninstall-test-networks
kvm-uninstall-test-networks: kvm-uninstall-test-domains
	$(foreach network_file, $(KVM_TEST_NETWORK_FILES), \
		$(call destroy-kvm-network,$(notdir $(basename $(network_file))))$(crlf) \
		rm -f $(network_file)$(crlf))


#
# Build KVM domains from scratch
#

KVM_ISO = $(KVM_POOLDIR)/$(notdir $(KVM_ISO_URL))

.PHONY: kvm-iso
kvm-iso: $(KVM_ISO)
$(KVM_ISO): | $(KVM_POOLDIR)
	cd $(KVM_POOLDIR) && wget $(KVM_ISO_URL)

define check-kvm-domain
	: check-kvm-domain domain=$(1)
	if $(VIRSH) dominfo '$(1)' >/dev/null ; then : ; else \
		echo "" ; \
		echo "  ERROR: the domain $(1) seems to be missing; run 'make kvm-install'" ; \
		echo "" ; \
		exit 1 ; \
	fi
endef

define create-kvm-domain
	: create-kvm-domain path=$(1) domain=$(notdir $(1))
	$(VIRT_INSTALL) \
		--name $(notdir $(1)) \
		$(VIRT_OS_VARIANT) \
		--vcpus=1 \
		--memory 512 \
		--nographics \
		--disk cache=writeback,path=$(1).qcow2 \
		$(VIRT_CPU) \
		$(VIRT_GATEWAY) \
		$(VIRT_RND) \
		$(VIRT_SECURITY) \
		$(VIRT_SOURCEDIR) \
		$(VIRT_TESTINGDIR) \
		--import \
		--noautoconsole \
		--noreboot
	: Fixing up eth0, must be a better way ...
	$(KVMSH) --shutdown $(notdir $(1)) \
		sed -i -e '"s/HWADDR=.*/HWADDR=\"$$(cat /sys/class/net/e[n-t][h-s]?/address)\"/"' \
			/etc/sysconfig/network-scripts/ifcfg-eth0 \; \
		service network restart \; \
		ip address show scope global
endef

define destroy-kvm-domain
	: destroy-kvm-domain domain=$(1)
	if $(VIRSH) domstate $(1) 2>/dev/null | grep running > /dev/null ; then \
		$(VIRSH) destroy $(1) ; \
	fi
	if $(VIRSH) dominfo $(1) >/dev/null 2>&1 ; then \
		$(VIRSH) undefine $(1) ; \
	fi
endef



#
# Create + package install + package upgrade the base domain
#
# Create and upgrade the base domain and (as a side effect) the disk
# image.
#
# The package install is to ensure that all currently required
# packages are present (perhaps $(KVM_PACKAGES) changed), and the
# upgrade is to ensure that the latest version is installed (rather
# than an older version from the DVD image, say).
#
# Does the order matter?  Trying to upgrade an uninstalled package
# barfs.  And re-installing a package with a pending upgrade does
# nothing.
#
# To avoid unintended re-builds triggered by things like a git branch
# switch, this target is order-only dependent on its sources.
#
# The create the domain rule's target is .ks - moved into place
# right at the very end.  That way the problem of a virt-install crash
# leaving the disk-image in an incomplete state is avoided.
#
# The .upgraded target then depends on the .ks target.  This way an
# upgrade can be triggered without needing to rebuild the entire base
# domain.

.PRECIOUS: $(KVM_POOLDIR)/$(KVM_BASE_DOMAIN).ks
$(KVM_POOLDIR)/$(KVM_BASE_DOMAIN).ks: | $(KVM_ISO) $(KVM_KICKSTART_FILE) $(KVM_GATEWAY_FILE) $(KVM_POOLDIR)
	$(call check-kvm-qemu-directory)
	$(call destroy-kvm-domain,$(KVM_BASE_DOMAIN))
	: delete any old disk and let virt-install create the image
	rm -f '$(basename $@).qcow2'
	: Confirm that there is a tty - else virt-install fails mysteriously
	tty
	: XXX: Passing $(VIRT_SECURITY) to virt-install causes it to panic
	$(VIRT_INSTALL) \
		--name=$(KVM_BASE_DOMAIN) \
		$(VIRT_OS_VARIANT) \
		--vcpus=1 \
		--memory 1024 \
		--nographics \
		--disk size=$(VIRT_DISK_SIZE_GB),cache=writeback,path=$(basename $@).qcow2 \
		$(VIRT_CPU) \
		$(VIRT_GATEWAY) \
		$(VIRT_RND) \
		$(VIRT_SOURCEDIR) \
		$(VIRT_TESTINGDIR) \
		--location=$(KVM_ISO) \
		--initrd-inject=$(KVM_KICKSTART_FILE) \
		--extra-args="swanname=$(KVM_BASE_DOMAIN) ks=file:/$(notdir $(KVM_KICKSTART_FILE)) console=tty0 console=ttyS0,115200 net.ifnames=0 biosdevname=0" \
		--noreboot
	: the reboot message from virt-install can be ignored
	touch $@

$(KVM_POOLDIR)/$(KVM_BASE_DOMAIN).upgraded: $(KVM_POOLDIR)/$(KVM_BASE_DOMAIN).ks
	$(call check-kvm-qemu-directory)
	$(if $(KVM_PACKAGES), \
		$(KVMSH) $(KVM_BASE_DOMAIN) $(KVM_PACKAGE_INSTALL) $(KVM_PACKAGES))
	$(if $(KVM_PACKAGES), \
		$(KVMSH) $(KVM_BASE_DOMAIN) $(KVM_PACKAGE_UPGRADE) $(KVM_PACKAGES))
	$(if $(KVM_INSTALL_RPM_LIST), \
		$(KVMSH) $(KVM_BASE_DOMAIN) $(KVM_INSTALL_RPM_LIST))
	$(if $(KVM_DEBUGINFO), \
		$(KVMSH) $(KVM_BASE_DOMAIN) $(KVM_DEBUGINFO_INSTALL) $(KVM_DEBUGINFO))
	$(MAKE) kvm-shutdown-base-domain
	touch $@

.PHONY: kvm-upgrade-base-domain
kvm-upgrade-base-domain:
	rm -f $($(KVM_POOLDIR)/$(KVM_BASE_DOMAIN).upgraded)
	$(MAKE) kvm-install-base-domain

.PHONY: install-kvm-domain-$(KVM_BASE_DOMAIN)
install-kvm-domain-$(KVM_BASE_DOMAIN): $(KVM_POOLDIR)/$(KVM_BASE_DOMAIN).upgraded

#
# Create the local disk images
#

.PRECIOUS: $(foreach domain, $(KVM_LOCAL_DOMAINS), $(KVM_LOCALDIR)/$(domain).qcow2)

# Create the local disk images from clone

define shadow-kvm-disk
	:
	: shadow-kvm-disk from=$(1) to=$(2)
	:
	: Fix any disk modes - qemu changes them under the hood
	: If this fails, the step:
	:   https://libreswan.org/wiki/Test_Suite#Setting_Users_and_Groups
	: was probably missed
	groups | grep $(KVM_GROUP)
	test -r $(1) || sudo chgrp $(KVM_GROUP) $(1)
	test -r $(1) || sudo chmod g+r          $(1)
	test -r $(1)
	test -w $(dir $(2))
	: shutdown from
	$(KVMSH) --shutdown $(basename $(notdir $(1)))
	: create a shadow - from is used as a backing store
	rm -f $(2)
	qemu-img create -f qcow2 -b $(1) $(2)
endef

KVM_BASE_DISK_CLONES = $(addsuffix .qcow2, $(addprefix $(KVM_LOCALDIR)/, $(KVM_BASE_DOMAIN_CLONES)))
$(KVM_BASE_DISK_CLONES): | $(KVM_POOLDIR)/$(KVM_BASE_DOMAIN).upgraded $(KVM_LOCALDIR)
	: copy-base-disk from=$< to=$@
	$(call check-kvm-qemu-directory)
	$(MAKE) kvm-shutdown-base-domain
	test -r $(KVM_POOLDIR)/$(KVM_BASE_DOMAIN).qcow2 || sudo chgrp $(KVM_GROUP) $(KVM_POOLDIR)/$(KVM_BASE_DOMAIN).qcow2
	test -r $(KVM_POOLDIR)/$(KVM_BASE_DOMAIN).qcow2 || sudo chmod g+r          $(KVM_POOLDIR)/$(KVM_BASE_DOMAIN).qcow2
	: if this test fails, user probably forgot this step:
	: https://libreswan.org/wiki/Test_Suite#Setting_Users_and_Groups
	test -r $(KVM_POOLDIR)/$(KVM_BASE_DOMAIN).qcow2
	$(call shadow-kvm-disk,$(KVM_POOLDIR)/$(KVM_BASE_DOMAIN).qcow2,$@.tmp)
	mv $@.tmp $@

KVM_BUILD_DISK_CLONES = $(addsuffix .qcow2, $(addprefix $(KVM_LOCALDIR)/, $(KVM_BUILD_DOMAIN_CLONES)))
$(KVM_BUILD_DISK_CLONES): | $(KVM_LOCALDIR)/$(KVM_BUILD_DOMAIN).qcow2 $(KVM_LOCALDIR)
	: copy-build-disk $@
	$(call check-kvm-qemu-directory)
	$(call shadow-kvm-disk,$(KVM_LOCALDIR)/$(KVM_BUILD_DOMAIN).qcow2,$@.tmp)
	mv $@.tmp $@

#
# Create the local domains
#

# Since running a domain will likely modify its .qcow2 disk image
# (changing MTIME), the domain's disk isn't a good indicator that a
# domain needs updating.  Instead use the .xml file to indicate that a
# domain has been created.

.PRECIOUS: $(foreach domain, $(KVM_LOCAL_DOMAINS), $(KVM_LOCALDIR)/$(domain).xml)

#
# Create the "build" domain (if unique)
#
# Depend on a fully constructed $(KVM_BASE_DOMAIN) (and not just that
# domain's disk image).  If make creates the $(KVM_BUILD_DOMAIN)
# before $(KVM_BASE_DOMAIN) then virt-install complains that
# $(KVM_BASE_DOMAIN)'s disk is already in use.
#

$(KVM_LOCALDIR)/$(KVM_BUILD_DOMAIN).xml: \
		| \
		$(KVM_BASE_GATEWAY_FILE) \
		$(KVM_POOLDIR)/$(KVM_BASE_DOMAIN).upgraded \
		$(KVM_LOCALDIR)/$(KVM_BUILD_DOMAIN).qcow2
	: build-domain $@
	$(call check-kvm-qemu-directory)
	$(call destroy-kvm-domain,$(KVM_BUILD_DOMAIN))
	$(call create-kvm-domain,$(KVM_LOCALDIR)/$(KVM_BUILD_DOMAIN))
	$(VIRSH) dumpxml $(KVM_BUILD_DOMAIN) > $@.tmp
	mv $@.tmp $@
.PHONY: install-kvm-domain-$(KVM_BUILD_DOMAIN)
install-kvm-domain-$(KVM_BUILD_DOMAIN): $(KVM_LOCALDIR)/$(KVM_BUILD_DOMAIN).xml

#
# Create the test domains
#

define install-kvm-test-domain
  #(info install-kvm-test-domain prefix=$(1) host=$(2) domain=$(1)$(2))
  .PHONY: install-kvm-domain-$(1)$(2)
  install-kvm-domain-$(1)$(2): $$(KVM_LOCALDIR)/$(1)$(2).xml
  $$(KVM_LOCALDIR)/$(1)$(2).xml: \
		| \
		$$(foreach subnet,$$(KVM_TEST_SUBNETS), \
			$$(KVM_POOLDIR)/$(1)$$(subnet).net) \
		testing/libvirt/vm/$(2) \
		$(KVM_LOCALDIR)/$(1)$(2).qcow2
	: install-kvm-test-domain prefix=$(1) host=$(2)
	$$(call check-kvm-qemu-directory)
	$$(call destroy-kvm-domain,$(1)$(2))
	sed \
		-e "s:@@NAME@@:$(1)$(2):" \
		-e "s:@@TESTINGDIR@@:$$(KVM_TESTINGDIR):" \
		-e "s:@@SOURCEDIR@@:$$(KVM_SOURCEDIR):" \
		-e "s:@@POOLSPACE@@:$$(KVM_LOCALDIR):" \
		-e "s:@@USER@@:$$(KVM_UID):" \
		-e "s:@@GROUP@@:$$(KVM_GID):" \
		-e "s:network='192_:network='$(1)192_:" \
		< 'testing/libvirt/vm/$(2)' \
		> '$$@.tmp'
	$$(VIRSH) define $$@.tmp
	mv $$@.tmp $$@
endef

$(foreach prefix, $(KVM_PREFIXES), \
	$(foreach host,$(KVM_TEST_HOSTS), \
		$(eval $(call install-kvm-test-domain,$(call strip-prefix,$(prefix)),$(host)))))


#
# Rules to uninstall individual domains
#

define uninstall-kvm-domain-DOMAIN
  #(info uninstall-kvm-domain-DOMAIN domain=$(1) dir=$(2))
  .PHONY: uninstall-kvm-domain-$(1)
  uninstall-kvm-domain-$(1):
	: uninstall-kvm-domain domain=$(1) dir=$(2)
	$$(call destroy-kvm-domain,$(1))
	rm -f $(2)/$(1).xml
	rm -f $(2)/$(1).upgraded
	rm -f $(2)/$(1).ks
	rm -f $(2)/$(1).qcow2
	rm -f $(2)/$(1).img
endef

$(foreach domain, $(KVM_BASE_DOMAIN), \
	$(eval $(call uninstall-kvm-domain-DOMAIN,$(domain),$(KVM_POOLDIR))))
$(foreach domain, $(KVM_BUILD_DOMAIN) $(KVM_TEST_DOMAINS), \
	$(eval $(call uninstall-kvm-domain-DOMAIN,$(domain),$(KVM_LOCALDIR))))

# Direct dependencies.  This is so that a primitive like
# uninstall-kvm-domain-clone isn't run until all its dependencies,
# such as uninstall-kvm-domain-build, have been run.  Using
# kvm-uninstall-* rules leads to indirect dependencies and
# out-of-order destruction.

$(addprefix uninstall-kvm-domain-, $(KVM_BUILD_DOMAIN)): \
	$(addprefix uninstall-kvm-domain-, $(KVM_BUILD_DOMAIN_CLONES))

#
# Generic kvm-* rules, point at the *-kvm-* primitives defined
# elsewhere.
#

define kvm-hosts-domains
  #(info kvm-host-domains rule=$(1)

  .PHONY: kvm-$(1)-base-domain
  kvm-$(1)-base-domain: $$(addprefix $(1)-kvm-domain-, $$(KVM_BASE_DOMAIN))

  .PHONY: kvm-$(1)-build-domain
  kvm-$(1)-build-domain: $$(addprefix $(1)-kvm-domain-, $$(KVM_BUILD_DOMAIN))

  .PHONY: kvm-$(1)-basic-domains
  kvm-$(1)-basic-domains: $$(addprefix $(1)-kvm-domain-, $$(KVM_BASIC_DOMAINS))

  .PHONY: kvm-$(1)-install-domains
  kvm-$(1)-install-domains: $$(addprefix $(1)-kvm-domain-, $$(KVM_INSTALL_DOMAINS))

  .PHONY: kvm-$(1)-test-domains
  kvm-$(1)-test-domains: $$(addprefix $(1)-kvm-domain-, $$(KVM_TEST_DOMAINS))

  .PHONY: kvm-$(1)-local-domains
  kvm-$(1)-local-domains: $$(addprefix $(1)-kvm-domain-, $$(KVM_LOCAL_DOMAINS))

endef

$(eval $(call kvm-hosts-domains,install))

$(eval $(call kvm-hosts-domains,uninstall))

$(eval $(call kvm-hosts-domains,shutdown))

#
# Get rid of (almost) everything
#
# After a purge, there should be an upgrade.  Force this by deleting
# the .upgraded file.
#
# XXX: don't depend on targets that trigger a KVM build.

.PHONY: kvm-purge
kvm-purge: kvm-clean kvm-uninstall-test-networks kvm-uninstall-local-domains
	rm -f $(KVM_POOLDIR)/$(KVM_BASE_DOMAIN).upgraded

.PHONY: kvm-demolish
kvm-demolish: kvm-purge kvm-uninstall-base-network kvm-uninstall-base-domain

.PHONY: kvm-clean clean-kvm
kvm-clean clean-kvm: kvm-shutdown-local-domains kvm-clean-keys kvm-clean-tests
	: 'make kvm-DOMAIN-make-clean' to invoke clean on a DOMAIN
	rm -rf $(KVM_OBJDIR)


#
# Build targets
#
# Map the documented targets, and their aliases, onto
# internal/canonical targets.

#
# kvm-build and kvm-HOST|DOMAIN-build
#
# To avoid "make base" and "make module" running in parallel on the
# build machine (stepping on each others toes), this uses two explicit
# commands (each invokes make on the domain) to ensre that "make base"
# and "make modules" are serialized.
#
# Shutdown the domains before building.  The build domain won't boot
# when its clones are running.

define kvm-DOMAIN-build
  #(info kvm-DOMAIN-build domain=$(1))
  .PHONY: kvm-$(1)-build
  kvm-$(1)-build: | $$(KVM_LOCALDIR)/$(1).xml
	: kvm-DOMAIN-build domain=$(1)
	$(call check-kvm-qemu-directory)
	$$(KVMSH) $$(KVMSH_FLAGS) --chdir . $(1) 'export OBJDIR=$$(KVM_OBJDIR)'
	$$(KVMSH) $$(KVMSH_FLAGS) --chdir . $(1) 'make OBJDIR=$$(KVM_OBJDIR) $$(KVM_MAKEFLAGS) base'
ifeq ($(USE_KLIPS),true)
	$$(KVMSH) $$(KVMSH_FLAGS) --chdir . $(1) 'make OBJDIR=$$(KVM_OBJDIR) $$(KVM_MAKEFLAGS) module'
endif
	: install will run $$(KVMSH) --shutdown $(1)
endef

$(foreach domain, $(KVM_LOCAL_DOMAINS), \
	$(eval $(call kvm-DOMAIN-build,$(domain))))
$(foreach host, $(filter-out $(KVM_DOMAINS), $(KVM_LOCAL_HOSTS)), \
	$(eval $(call kvm-HOST-DOMAIN,kvm-,$(host),-build)))

.PHONY: kvm-build
kvm-build: $(foreach domain, $(KVM_INSTALL_DOMAINS), uninstall-kvm-domain-$(domain))
	$(MAKE) kvm-$(KVM_BUILD_DOMAIN)-build


#
# kvm-install and kvm-HOST|DOMAIN-install
#
# "kvm-DOMAIN-install" can't start until the common
# kvm-$(KVM_BUILD_DOMAIN)-build has completed.
#
# After installing shut down the domain.  Otherwise, when KVM_PREFIX
# is large, the idle domains consume huge amounts of memory.
#
# When KVM_PREFIX is large, "make kvm-install" is dominated by the
# below target.  It should be possible to instead create one domain
# with everything installed and then clone it.

define kvm-DOMAIN-install
  #(info kvm-DOMAIN-install domain=$(1))
  .PHONY: kvm-$(1)-install
  kvm-$(1)-install: kvm-$$(KVM_BUILD_DOMAIN)-build | $$(KVM_LOCALDIR)/$(1).xml
	: kvm-DOMAIN-install domain=$(1)
	$(call check-kvm-qemu-directory)
	$$(KVMSH) $$(KVMSH_FLAGS) --chdir . $(1) 'make OBJDIR=$$(KVM_OBJDIR) $$(KVM_MAKEFLAGS) install-base'
ifeq ($(USE_KLIPS),true)
	$$(KVMSH) $$(KVMSH_FLAGS) --chdir . $(1) 'make OBJDIR=$$(KVM_OBJDIR) $$(KVM_MAKEFLAGS) module_install'
endif
ifeq ($(USE_FIPSCHECK),true)
	$$(KVMSH) $$(KVMSH_FLAGS) --chdir . $(1) 'make OBJDIR=$$(KVM_OBJDIR) $$(KVM_MAKEFLAGS) install-fipshmac'
endif
	$$(KVMSH) $$(KVMSH_FLAGS) --chdir . $(1) 'restorecon /usr/local/sbin /usr/local/libexec/ipsec -Rv'
	$$(KVMSH) $$(KVMSH_FLAGS) --chdir . $(1) 'sed -i "s/Restart=always/Restart=no/" /lib/systemd/system/ipsec.service'
	$$(KVMSH) $$(KVMSH_FLAGS) --chdir . $(1) 'systemctl disable ipsec.service'
	: $$(KVMSH) $$(KVMSH_FLAGS) --chdir . $(1) 'systemctl daemon-reload'
	$$(KVMSH) --shutdown $(1)
endef

$(foreach domain, $(KVM_LOCAL_DOMAINS), \
	$(eval $(call kvm-DOMAIN-install,$(domain))))
$(foreach host, $(filter-out $(KVM_DOMAINS), $(KVM_LOCAL_HOSTS)), \
	$(eval $(call kvm-HOST-DOMAIN,kvm-,$(host),-install)))

#
# kvm-install
#
# So that all the INSTALL domains are deleted before the build domain
# is booted, this is done using a series of sub-makes (without this,
# things barf because the build domain things its disk is in use).

.PHONY: kvm-install
kvm-install: $(foreach domain, $(KVM_INSTALL_DOMAINS), uninstall-kvm-domain-$(domain))
	$(MAKE) kvm-$(KVM_BUILD_DOMAIN)-install
	$(MAKE) $(foreach domain, $(KVM_TEST_DOMAINS), install-kvm-domain-$(domain))

#
# kvm-uninstall
#
# Rather than just removing libreswan from the all the test (install)
# domains, this removes the test and build domains completely.  This
# way, in addition to giving kvm-install a 100% fresh start (no
# depdenence on 'make uninstall') the test run also gets entirely new
# domains.

.PHONY: kvm-uninstall
kvm-uninstall: $(addprefix uninstall-kvm-domain-, $(KVM_INSTALL_DOMAINS))
kvm-uninstall: $(addprefix uninstall-kvm-domain-, $(KVM_BASIC_DOMAINS))
kvm-uninstall: $(addprefix uninstall-kvm-domain-, $(KVM_BUILD_DOMAIN))


#
# kvmsh-HOST
#
# Map this onto the first domain group.  Logging into the other
# domains can be done by invoking kvmsh.py directly.
#

define kvmsh-DOMAIN
  #(info kvmsh-DOMAIN domain=$(1) file=$(2))
  .PHONY: kvmsh-$(1)
  kvmsh-$(1): | $(2)
	: kvmsh-DOMAIN domain=$(1) file=$(2)
	$(call check-kvm-qemu-directory)
	$$(KVMSH) $$(KVMSH_FLAGS) $(1) $(KVMSH_COMMAND)
endef

$(foreach domain, $(KVM_BASE_DOMAIN), \
	$(eval $(call kvmsh-DOMAIN,$(domain),$$(KVM_POOLDIR)/$$(KVM_BASE_DOMAIN).ks)))

$(foreach domain,  $(KVM_LOCAL_DOMAINS), \
	$(eval $(call kvmsh-DOMAIN,$(domain),$$(KVM_LOCALDIR)/$(domain).xml)))

$(foreach host, $(filter-out $(KVM_DOMAINS), $(KVM_HOSTS)), \
	$(eval $(call kvm-HOST-DOMAIN,kvmsh-,$(host))))

.PHONY: kvmsh-base
kvmsh-base: kvmsh-$(KVM_BASE_DOMAIN)

.PHONY: kvmsh-build
kvmsh-build: kvmsh-$(KVM_BUILD_DOMAIN)


#
# Shutdown domains and hosts.
#

# Generate rules to shut down all the domains (kvm-shutdown) and
# individual domains (kvm-shutdown-domain).
#
# Don't require the domains to exist.

define shutdown-kvm-domain
  #(info shutdown-kvm-domain domain=$(1))
  .PHONY: shutdown-kvm-domain-$(1)
  shutdown-kvm-domain-$(1):
	: shutdown-kvm-domain domain=$(1)
	echo ; \
	if $(VIRSH) dominfo $(1) > /dev/null 2>&1 ; then \
		$(KVMSH) --shutdown $(1) || exit 1 ; \
	else \
		echo Domain $(1) does not exist ; \
	fi ; \
	echo
endef

$(foreach domain, $(KVM_DOMAINS), \
	$(eval $(call shutdown-kvm-domain,$(domain))))

.PHONY: kvm-shutdown
kvm-shutdown: $(addprefix shutdown-kvm-domain-,$(KVM_DOMAINS))

.PHONY: kvm-shutdown-install-domains
kvm-shutdown-install-domains: $(addprefix shutdown-kvm-domain-,$(KVM_INSTALL_DOMAINS))

.PHONY: kvm-shutdown-test-domains
kvm-shutdown-test-domains: $(addprefix shutdown-kvm-domain-,$(KVM_TEST_DOMAINS))

.PHONY: kvm-shutdown-local-domains
kvm-shutdown-local-domains: $(addprefix shutdown-kvm-domain-,$(KVM_LOCAL_DOMAINS))

#
# Some hints
#
# Only what is listed in here is "supported"
#

empty =
comma = ,
sp = $(empty) $(empty)
# the first blank line is ignored
define crlf


endef

define kvm-var-value
$(1)=$($(1)) [$(value $(1))]
endef

define kvm-value
$($(1)) [$(value $(1))]
endef

define kvm-var
$($(1)) [$$($(1))]
endef

define kvm-config

Configuration:

  Makefile variables:

    $(call kvm-var-value,KVM_SOURCEDIR)
    $(call kvm-var-value,KVM_TESTINGDIR)
    $(call kvm-var-value,KVM_PREFIXES)
    $(call kvm-var-value,KVM_WORKERS)
    $(call kvm-var-value,KVM_GROUP)
    $(call kvm-var-value,KVM_UID)
    $(call kvm-var-value,KVM_GID)
    $(call kvm-var-value,KVM_CONNECTION)
    $(call kvm-var-value,KVM_MAKEFLAGS)
    $(call kvm-var-value,KVM_POOLDIR)$(if $(wildcard $(KVM_POOLDIR)),, [MISSING])
	default directory for storing VM files
    $(call kvm-var-value,KVM_POOLDIR)$(if $(wildcard $(KVM_POOLDIR)),, [MISSING])
	directory for storing the shared base (master) VM;
	should be relatively permanent storage
    $(call kvm-var-value,KVM_LOCALDIR)$(if $(wildcard $(KVM_LOCALDIR)),, [MISSING])
	directory for storing the VMs local to this build tree;
	can be temporary storage (for instance /tmp)
    $(call kvm-var-value,KVM_GATEWAY)
	the shared NATting gateway;
	used by the base (master) domain along with any local domains
	when internet access is required
    $(call kvm-var-value,KVM_OS)
    $(call kvm-var-value,KVM_KICKSTART_FILE)
    $(call kvm-var-value,KVM_GATEWAY)
    $(call kvm-var-value,KVM_BASE_HOST)
    $(call kvm-var-value,KVM_BASE_DOMAIN)
    $(call kvm-var-value,KVM_BUILD_HOST)
    $(call kvm-var-value,KVM_BUILD_DOMAIN)
    $(call kvm-var-value,KVM_TEST_SUBNETS)
    $(call kvm-var-value,KVM_TEST_NETWORKS)
    $(call kvm-var-value,KVM_TEST_NETWORK_FILES)
    $(call kvm-var-value,KVM_TEST_HOSTS)
    $(call kvm-var-value,KVM_TEST_DOMAINS)

 KVM Domains:

    $(call kvm-value,KVM_BASE_DOMAIN)
    |
    | gateway: $(call kvm-value,KVM_GATEWAY)
    | directory: $(call kvm-value,KVM_POOLDIR)
    |
    + $(call kvm-value,KVM_BUILD_DOMAIN)
    | |
    | | gateway: $(call kvm-value,KVM_GATEWAY)
    | | directory: $(call kvm-value,KVM_LOCALDIR)
    | |  \
$(foreach prefix,$(KVM_PREFIXES), \
  \
  $(crlf)$(sp)$(sp)$(sp)$(sp)|$(sp)| test group $(prefix) \
  $(crlf)$(sp)$(sp)$(sp) +---- basic: \
  $(foreach basic,$(KVM_BASIC_HOSTS),$(call strip-prefix,$(prefix))$(basic)) \
  \
  $(crlf)$(sp)$(sp)$(sp)$(sp)| +-- install: \
  $(foreach install,$(KVM_INSTALL_HOSTS),$(call strip-prefix,$(prefix))$(install)) \
  \
  $(crlf)$(sp)$(sp)$(sp)$(sp)|$(sp)|$(sp$)$(sp)$(sp) networks: \
  $(foreach network, $(KVM_TEST_SUBNETS),$(call strip-prefix,$(prefix))$(network)) \
  \
  $(crlf)$(sp)$(sp)$(sp)$(sp)|$(sp)| \
)
endef

define kvm-help

Domains and networks:

  These directly manipulate the underling domains and networks and are
  not not generally recommended.  For the most part kvm-install and
  kvm-unsintall are sufficient.

  Domains:

    kvm-install-base-domain (kvm-uninstall-base-domain)
        - (un)install the base domain
        - install dependencies: base gateway
    kvm-install-build-domain (kvm-uninstall-build-domain)
        - (un)install this directory's build domain
        - install dependencies: local gateway; test networks
    kvm-install-test-domains (kvm-uninstall-test-domains)
        - (un)install this directory's test domains
        - install dependencies: build domain; test networks
    kvm-install-local-domains (kvm-uninstall-local-domains)
        - (un)install this directory's  build and test domains
        - install dependencies: see above

  Networks:

    kvm-install-gateway (kvm-uninstall-gateway)
        - (un)install the NATting base gateway used by the base
          and build domains
	- uninstall dependencies: base domain
    kvm-install-test-networks (kvm-uninstall-test-networks)
        - (un)install the test networks used by this
          directory's test domains
        - uninstall dependencies: test domains

Standard targets and operations:

  Try to delete (almost) everything:

    kvm-purge
        - delete build, and test domains, test networks, test results, and
          test build
        - force a base domain upgrade
    kvm-demolish
        - also delete the base domain

  Manipulating and accessing (loging into) domains:

    kvmsh-base kvmsh-build
    kvmsh-HOST ($(filter-out build, $(KVM_TEST_HOSTS)))
        - use 'virsh console' to login to the given domain
	- for HOST login to the first domain vis $(addprefix $(KVM_FIRST_PREFIX), HOST)
        - if necessary, create and boot the host
    $(addprefix kvmsh-, $(KVM_LOCAL_DOMAINS))
        - login to the specific domain
        - if necessary, create and boot the domain

    kvm-shutdown
        - shutdown all domains

  To build or delete the keys used when testing:

    kvm-keys (kvm-clean-keys)
        - use the local build domain to create the test keys

  To set things up for a test run:

    kvm-install: install (or update) libreswan on the test domains
	- cheats by building/installing using the local build domain
          ($(KVM_BUILD_DOMAIN)) and then cloning it to create the test domains
	- if necessary, creates the local build domain ($(KVM_BUILD_DOMAIN))
          from the local base domain ($(KVM_BASE_DOMAIN))
	- if necessary, creates and upgrade the local base domain
	  ($(KVM_BASE_DOMAIN))

    kvm-uninstall: uninstall libreswan from the the test domains
	- cheats by deleting the build and test domains

    kvm-clean: cleans the directory forcing 'kvm-install' to perform a 'clean' build
	- deletes the test domains
	- deletes the build domain ($(KVM_BUILD_DOMAIN))
	- deletes the test keys so the next kvm-check builds fresh keys
	- deletes the test results from the previous test run

  To run the testsuite against libreswan installed on the test domains
  (see "make kvm-install" above):

    kvm-check         - run all GOOD tests against the
                        previously installed libreswan
    kvm-check KVM_TESTS+=testing/pluto/basic-pluto-0[0-1]
                      - run test matching the pattern
    kvm-check KVM_TEST_FLAGS='--test-status "good|wip"'
                      - run both good and wip tests
    kvm-recheck       - like kvm-check but skip tests that
                        passed during the previous kvm-check
    kvm-check-clean   - delete the test OUTPUT/ directories

    distclean         - scrubs the source tree (but don't touch the KVMS)

  To analyze test results:

    kvm-results       - list the tests and their results
    kvm-diffs         - list the tests and their differences
    kvm-check-modified
                      - run any tests with modified files
    kvm-diff-modified
                      - list any modified tests and their differences

  To print make variables:

    print-kvm-prefixes    print prefixes being used

endef

.PHONY: kvm-help
kvm-help:
	$(info $(kvm-help))
	$(info For more details see "make kvm-config" and "make web-config")

.PHONY: kvm-config
kvm-config:
	$(info $(kvm-config))
