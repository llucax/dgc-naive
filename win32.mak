# Makefile to build the garbage collector D library for Win32
# Designed to work with DigitalMars make
# Targets:
#	make
#		Same as make all
#	make lib
#		Build the garbage collector library
#   make doc
#       Generate documentation
#	make clean
#		Delete unneeded files created by build process

LIB_BASE=tango-gc-naive
LIB_BUILD=
LIB_TARGET=$(LIB_BASE)$(LIB_BUILD).lib
LIB_MASK=$(LIB_BASE)*.lib

CP=xcopy /y
RM=del /f
MD=mkdir

ADD_CFLAGS=
ADD_DFLAGS=

CFLAGS_RELEASE=-mn -6 -r $(ADD_CFLAGS)
CFLAGS_DEBUG=-g -mn -6 -r $(ADD_CFLAGS)
DFLAGS_RELEASE=-release -O -inline -w -nofloat -I. -I../shared -I../../.. $(ADD_DFLAGS)
DFLAGS_DEBUG=-g -w -nofloat  -I. -I../shared -I../../.. $(ADD_DFLAGS)
TFLAGS_RELEASE=-O -inline -w  -nofloat $(ADD_DFLAGS)
TFLAGS_DEBUG=-g -w -nofloat $(ADD_DFLAGS)

CFLAGS=$(CFLAGS_RELEASE)
DFLAGS=$(DFLAGS_RELEASE)
TFLAGS=$(TFLAGS_RELEASE)

DOCFLAGS=-version=DDoc

CC=dmc
LC=lib
DC=dmd

LIB_DEST=..

.DEFAULT: .asm .c .cpp .d .html .obj

.asm.obj:
	$(CC) -c $<

.c.obj:
	$(CC) -c $(CFLAGS) $< -o$@

.cpp.obj:
	$(CC) -c $(CFLAGS) $< -o$@

.d.obj:
	$(DC) -c $(DFLAGS) $< -of$@

.d.html:
	$(DC) -c -o- $(DOCFLAGS) -Df$*.html $<
#	$(DC) -c -o- $(DOCFLAGS) -Df$*.html dmd.ddoc $<

targets : lib doc
all     : lib doc
lib     : naive.lib
doc     : naive.doc

######################################################

ALL_OBJS= \
    gc/iface.obj \
    gc/gc.obj \
    gc/arch.obj \
    gc/list.obj \
    gc/cell.obj \
    gc/dynarray.obj

######################################################

ALL_DOCS=

######################################################

naive.lib : $(LIB_TARGET)

$(LIB_TARGET) : $(ALL_OBJS)
	$(RM) $@
	$(LC) -c -n $@ $(ALL_OBJS)

naive.doc : $(ALL_DOCS)
	@echo No documentation available.

######################################################

clean :
	$(RM) /s *.di
	$(RM) $(ALL_OBJS)
	$(RM) $(ALL_DOCS)
	$(RM) $(LIB_MASK)

install :
	$(MD) $(LIB_DEST)
	$(CP) $(LIB_MASK) $(LIB_DEST)\.
