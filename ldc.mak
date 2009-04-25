# Makefile to build the garbage collector D library for LDC
# Designed to work with GNU make
# Targets:
#	make
#		Same as make all
#	make lib
#		Build the garbage collector library
#   make doc
#       Generate documentation
#	make clean
#		Delete unneeded files created by build process

LIB_TARGET_BC=libtango-gc-naive-bc.a
LIB_TARGET_NATIVE=libtango-gc-naive.a
LIB_TARGET_SHARED=libtango-gc-naive-shared.so
LIB_MASK=libtango-gc-naive*.*

CP=cp -f
RM=rm -f
MD=mkdir -p

ADD_CFLAGS=
ADD_DFLAGS=

#CFLAGS=-O3 $(ADD_CFLAGS)
CFLAGS=$(ADD_CFLAGS)

#DFLAGS=-release -O3 -inline -w -nofloat $(ADD_DFLAGS)
DFLAGS=-w -disable-invariants $(ADD_DFLAGS)

#TFLAGS=-O3 -inline -w -nofloat $(ADD_DFLAGS)
TFLAGS=-w -disable-invariants $(ADD_DFLAGS)

DOCFLAGS=-version=DDoc

CC=gcc
LC=llvm-ar rsv
LCC=llc
LLINK=llvm-link
CLC=ar rsv
LD=llvm-ld
DC=ldc

LIB_DEST=..

.SUFFIXES: .s .S .c .cpp .d .html .o .bc

.s.o:
	$(CC) -c $(CFLAGS) $< -o$@

.S.o:
	$(CC) -c $(CFLAGS) $< -o$@

.c.o:
	$(CC) -c $(CFLAGS) $< -o$@

.cpp.o:
	g++ -c $(CFLAGS) $< -o$@

.d.o:
	$(DC) -c $(DFLAGS) $< -of$@ -output-bc

.d.html:
	$(DC) -c -o- $(DOCFLAGS) -Df$*.html $<
#	$(DC) -c -o- $(DOCFLAGS) -Df$*.html dmd.ddoc $<

targets : lib sharedlib doc
all     : lib sharedlib doc
lib     : naive.lib naive.nlib
sharedlib : naive.sharedlib
doc     : naive.doc

######################################################

ALL_OBJS_BC= \
    gc/iface.bc \
    gc/gc.bc \
    gc/arch.bc \
    gc/list.bc \
    gc/cell.bc \
    gc/dynarray.bc

ALL_OBJS_O= \
    gc/iface.o \
    gc/gc.o \
    gc/arch.o \
    gc/list.o \
    gc/cell.o \
    gc/dynarray.o

######################################################

ALL_DOCS=

######################################################

naive.lib : $(LIB_TARGET_BC)
naive.nlib : $(LIB_TARGET_NATIVE)
naive.sharedlib : $(LIB_TARGET_SHARED)

$(LIB_TARGET_BC) : $(ALL_OBJS_O)
	$(RM) $@
	$(LC) $@ $(ALL_OBJS_BC)


$(LIB_TARGET_NATIVE) : $(ALL_OBJS_O)
	$(RM) $@
	$(CLC) $@ $(ALL_OBJS_O)


$(LIB_TARGET_SHARED) : $(ALL_OBJS_O)
	$(RM) $@
	$(CC) -shared -o $@ $(ALL_OBJS_O)

naive.doc : $(ALL_DOCS)
	echo No documentation available.

######################################################

clean :
	find . -name "*.di" | xargs $(RM)
	$(RM) $(ALL_OBJS_BC)
	$(RM) $(ALL_OBJS_O)
	$(RM) $(ALL_DOCS)

clean-all: clean
	$(RM) $(LIB_MASK)

install :
	$(MD) $(LIB_DEST)
	$(CP) $(LIB_MASK) $(LIB_DEST)/.
