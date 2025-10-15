SHELL := /bin/bash

AVM_LOCAL_TOOLS := $(CURDIR)/tools
export PATH := $(AVM_LOCAL_TOOLS):$(PATH)

include avmmakefile
